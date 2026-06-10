import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

import '../theme/app_theme.dart';
import '../background_service_helper.dart';
import '../services/rating_settings.dart';
import '../services/physio_simulator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../ema_and_gad7.dart';
import '../profile_page.dart';
import '../services/api_service.dart';
import 'baseline_calibration_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Page — Physiological Monitoring
// ─────────────────────────────────────────────────────────────────────────────

class DashboardPage extends StatefulWidget {
  final String? userId;
  const DashboardPage({super.key, this.userId});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  String _cachedId = "";
  bool _isServiceRunning = false;
  bool _isOptimized = false;

  // ── Prediction Pipeline State ──────────────────────────────
  String _predictionStatus = "loading"; // "loading", "buffering", "not_calibrated", "success", "error"
  List<double> _forecastData = [];
  String _statusMessage = "";
  Timer? _predictionTimer;
  int _bufferingCountdown = 60;
  Timer? _bufferingTimer;

  // ── Physiological Simulator ──────────────────────────────────
  final PhysioSimulator _simulator = PhysioSimulator();
  PhysioSnapshot _snapshot = const PhysioSnapshot(
    heartRate: 72,
    breathingRate: 16,
    bodyTemp: 36.6,
    motionMagnitude: 0.3,
  );

  // ── Animation Controllers ───────────────────────────────────
  late AnimationController _riskPulseController;
  late Animation<double> _riskPulseAnimation;

  late AnimationController _entryController;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
    _loadCachedId();

    // Risk indicator pulse animation
    _riskPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _riskPulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _riskPulseController, curve: Curves.easeInOut),
    );

    // Entry animation
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _entryFade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    ));
    _entryController.forward();

    // Start physiological data simulation
    _simulator.onData = (snap) {
      if (mounted) {
        setState(() => _snapshot = snap);
        _uploadPhysioData(snap);
      }
    };
    _simulator.start(interval: const Duration(seconds: 3));

    _startStatusCheck();
  }

  @override
  void dispose() {
    _simulator.stop();
    _riskPulseController.dispose();
    _entryController.dispose();
    _predictionTimer?.cancel();
    _bufferingTimer?.cancel();
    super.dispose();
  }

  // ── Data & Service Helpers ──────────────────────────────────

  Future<void> _loadCachedId() async {
    if (widget.userId != null) {
      setState(() => _cachedId = widget.userId!);
    } else {
      String id = await BackgroundServiceHelper.getCachedId();
      if (mounted) setState(() => _cachedId = id);
    }
    _startPredictionPolling();
  }

  // ── Forecast API Methods ────────────────────────────────────

  void _startPredictionPolling() {
    _predictionTimer?.cancel();
    _fetchForecast();
    // Poll the FastAPI prediction endpoint every 30 seconds
    _predictionTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchForecast();
    });
  }

  Future<void> _fetchForecast() async {
    if (_cachedId.isEmpty) return;

    final result = await ApiService.getEscalationForecast(_cachedId);
    if (!mounted) return;

    final status = result['status'] as String?;
    final message = result['message'] as String? ?? "";

    if (status == 'success') {
      final List? rawForecast = result['forecast'] as List?;
      final List<double> parsedForecast = rawForecast?.map((e) => (e as num).toDouble()).toList() ?? [];

      setState(() {
        _predictionStatus = "success";
        _forecastData = parsedForecast;
        _statusMessage = message;
      });

      _bufferingTimer?.cancel();
      _bufferingTimer = null;
    } else if (status == 'buffering') {
      setState(() {
        _predictionStatus = "buffering";
        _statusMessage = message;
      });
      _startBufferingCountdown();
    } else if (status == 'not_calibrated') {
      setState(() {
        _predictionStatus = "not_calibrated";
        _statusMessage = message;
      });
      _bufferingTimer?.cancel();
      _bufferingTimer = null;
    } else {
      // API Offline/Error state
      setState(() {
        if (_predictionStatus != "success") {
          _predictionStatus = "error";
        }
        _statusMessage = message;
      });
    }
  }

  void _startBufferingCountdown() {
    if (_bufferingTimer != null) return;
    _bufferingCountdown = 60;
    _bufferingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_bufferingCountdown > 0) {
          _bufferingCountdown--;
        } else {
          // Stay at 0, next periodic API fetch will resolve state change
        }
      });
    });
  }

  double _scaleForecastValue(double val) {
    // API outputs raw reconstruction errors from the LSTM-AE (typically 0.0 to 5.0)
    // We scale them by 20x for user presentation as a percentage (0% to 100%)
    if (val > 10.0) return val.clamp(0.0, 100.0);
    return (val * 20.0).clamp(0.0, 100.0);
  }

  List<double> get _effectiveForecastData {
    if (_forecastData.isNotEmpty) return _forecastData;
    // Fallback: If server is loading/buffering or offline, generate a smooth simulated forecast
    final startVal = _snapshot.riskScore;
    return List.generate(10, (i) {
      final drift = sin(i / 2.0) * 10.0 + (i * 0.5);
      return (startVal + drift).clamp(0.0, 100.0);
    });
  }

  void _startStatusCheck() {
    Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final isRunning = await FlutterBackgroundService().isRunning();
      final optimized = await Permission.ignoreBatteryOptimizations.isDenied;
      if (mounted) {
        setState(() {
          _isServiceRunning = isRunning;
          _isOptimized = optimized;
        });
        if (!isRunning) FlutterBackgroundService().startService();
      }
    });
  }

  Future<void> _uploadPhysioData(PhysioSnapshot snap) async {
    if (_cachedId.isEmpty) return;
    final data = {
      'heart_rate': snap.heartRate.toStringAsFixed(1),
      'breathing_rate': snap.breathingRate.toStringAsFixed(1),
      'body_temp': snap.bodyTemp.toStringAsFixed(2),
      'motion_magnitude': snap.motionMagnitude.toStringAsFixed(2),
      'risk_score': snap.riskScore.toStringAsFixed(1),
      'risk_label': snap.riskLabel,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await BackgroundServiceHelper.sendToSheet(
      _cachedId,
      'Physio_Vitals',
      data.toString(),
    );
  }

  void _showEmaSheet(String period) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmaRatingSheet(timePeriod: period),
    );
  }

  // ── Risk Score Color ────────────────────────────────────────
  Color _riskColor(double score) {
    if (score <= 20) return const Color(0xFF4CAF50);
    if (score <= 45) return const Color(0xFFFFA726);
    if (score <= 70) return const Color(0xFFFF7043);
    return const Color(0xFFEF5350);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Normal':
      case 'Still':
      case 'Low':
        return const Color(0xFF4CAF50);
      case 'Moderate':
      case 'Elevated':
      case 'Restless':
        return const Color(0xFFFFA726);
      case 'High':
      case 'Agitated':
        return const Color(0xFFEF5350);
      default:
        return Colors.grey;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final risk = _snapshot.riskScore;
    final riskCol = _riskColor(risk);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Physiological Monitor',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.kTextDark,
          ),
        ),
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppTheme.kTextDark, size: 20),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded,
                color: AppTheme.kTextDark),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppTheme.kTextDark),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RatingSettingsPage()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SlideTransition(
        position: _entrySlide,
        child: FadeTransition(
          opacity: _entryFade,
          child: _buildBody(risk, riskCol),
        ),
      ),
    );
  }

  Widget _buildBody(double risk, Color riskCol) {
    switch (_predictionStatus) {
      case 'loading':
        return _buildLoadingScreen();
      case 'not_calibrated':
        return _buildCalibrationRequiredScreen();
      case 'buffering':
        return _buildBufferingScreen();
      case 'error':
      case 'success':
      default:
        return _buildDashboardList(risk, riskCol);
    }
  }

  Widget _buildDashboardList(double risk, Color riskCol) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        // ── Connection Offline Warning Banner ──
        if (_predictionStatus == 'error') _buildOfflineBanner(),

        // ── Service Status Strip ──
        _buildServiceStrip(),
        if (_isOptimized) ...[
          const SizedBox(height: 10),
          _buildBatteryWarning(),
        ],

        const SizedBox(height: 20),

        // ── Risk Score Card ──
        _buildRiskCard(risk, riskCol),

        const SizedBox(height: 22),

        // ── KPI Grid (2x2) ──
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Heart Rate',
                value: _snapshot.heartRate.toStringAsFixed(0),
                unit: 'bpm',
                icon: Icons.monitor_heart_rounded,
                status: _snapshot.hrStatus,
                statusColor: _statusColor(_snapshot.hrStatus),
                gradient: const [Color(0xFFFF6B6B), Color(0xFFee5a24)],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _KpiCard(
                label: 'Breathing',
                value: _snapshot.breathingRate.toStringAsFixed(0),
                unit: 'br/min',
                icon: Icons.air_rounded,
                status: _snapshot.brStatus,
                statusColor: _statusColor(_snapshot.brStatus),
                gradient: const [Color(0xFF4facfe), Color(0xFF00f2fe)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Temperature',
                value: _snapshot.bodyTemp.toStringAsFixed(1),
                unit: '°C',
                icon: Icons.thermostat_rounded,
                status: _snapshot.tempStatus,
                statusColor: _statusColor(_snapshot.tempStatus),
                gradient: const [Color(0xFFF6D365), Color(0xFFFDA085)],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _KpiCard(
                label: 'Motion',
                value: _snapshot.motionMagnitude.toStringAsFixed(1),
                unit: 'g',
                icon: Icons.directions_run_rounded,
                status: _snapshot.motionStatus,
                statusColor: _statusColor(_snapshot.motionStatus),
                gradient: const [Color(0xFFA18CD1), Color(0xFFFBC2EB)],
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),
        _buildAdviceCard(risk),
        const SizedBox(height: 24),
        _buildChartsSection(),
        const SizedBox(height: 20),

        // ── Footer ──
        Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _cachedId.isNotEmpty
                  ? 'ID: $_cachedId  •  Live Monitoring'
                  : 'Initializing...',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppTheme.kTextLight),
            ),
          ),
        ),
      ],
    );
  }

  // ── Connection Status / Screen Swapping Builders ────────────

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.amber.shade800, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Server offline. Showing simulated forecast predictions.',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: Colors.amber.shade800, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.kPrimaryDeep),
          ),
          const SizedBox(height: 20),
          Text(
            'Connecting to prediction engine...',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.kTextLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrationRequiredScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: Colors.amber,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Calibration Required',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.kTextDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Aura needs to establish your calm resting baseline before the anxiety prediction engine can run accurately. Please complete a 3-minute resting calibration.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppTheme.kTextLight,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BaselineCalibrationPage(userId: _cachedId),
                    ),
                  ).then((_) => _fetchForecast());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.kPrimaryDeep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: Text(
                  'Start Baseline Calibration',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBufferingScreen() {
    final double progress = (60 - _bufferingCountdown) / 60.0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Establishing Sensor Stream',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.kTextDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Collecting initial physiological samples',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppTheme.kTextLight,
                ),
              ),
              const SizedBox(height: 36),

              // Countdown Ring
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.kPrimaryDeep),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_bufferingCountdown',
                        style: GoogleFonts.poppins(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.kTextDark,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        'seconds',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.kTextLight,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 36),

              Text(
                'Please sit quietly and breathe normally. Predictions will start immediately once the first 60-second window completes.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppTheme.kTextLight,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Pipeline steps check-list
              Column(
                children: [
                  _buildPipelineStepRow(true, 'Chest strap BLE connection active'),
                  const SizedBox(height: 10),
                  _buildPipelineStepRow(true, 'Baseline normalization parameters loaded'),
                  const SizedBox(height: 10),
                  _buildPipelineStepRow(
                    _bufferingCountdown == 0,
                    'Collecting first raw data window (700 Hz)',
                    trailing: _bufferingCountdown > 0 ? 'In progress' : null,
                  ),
                  const SizedBox(height: 10),
                  _buildPipelineStepRow(
                    false,
                    'Awaiting server feature extraction & predict',
                    trailing: _bufferingCountdown == 0 ? 'Connecting...' : 'Pending',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPipelineStepRow(bool complete, String text, {String? trailing}) {
    return Row(
      children: [
        Icon(
          complete ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          color: complete ? Colors.green : Colors.grey.shade400,
          size: 18,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              color: complete ? AppTheme.kTextDark : AppTheme.kTextLight,
              fontWeight: complete ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: complete ? Colors.green : AppTheme.kPrimaryDeep,
            ),
          ),
      ],
    );
  }

  Widget _buildForecastChart() {
    final List<double> forecast = _effectiveForecastData;
    final List<FlSpot> spots = List.generate(forecast.length, (index) {
      final yVal = _scaleForecastValue(forecast[index]);
      return FlSpot((index + 1).toDouble(), yVal);
    });

    double minY = 0.0;
    double maxY = 100.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.kPrimaryDeep.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: AppTheme.kPrimaryDeep,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '10-Minute Anxiety Forecast',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.kTextDark,
                      ),
                    ),
                    Text(
                      'Predictive stress escalation trajectory',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: AppTheme.kTextLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minX: 1,
                maxX: 10,
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.withValues(alpha: 0.08),
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        if (value < 1 || value > 10 || value % 2 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            '+${value.toInt()}m',
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              color: AppTheme.kTextLight,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 25,
                      getTitlesWidget: (value, meta) {
                        if (value < 0 || value > 100) return const SizedBox.shrink();
                        return Text(
                          '${value.toInt()}%',
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            color: AppTheme.kTextLight,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 20,
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.25),
                      strokeWidth: 1.5,
                      dashArray: [4, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          color: const Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600,
                        ),
                        labelResolver: (line) => 'Low',
                      ),
                    ),
                    HorizontalLine(
                      y: 45,
                      color: const Color(0xFFFFA726).withValues(alpha: 0.25),
                      strokeWidth: 1.5,
                      dashArray: [4, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          color: const Color(0xFFFFA726),
                          fontWeight: FontWeight.w600,
                        ),
                        labelResolver: (line) => 'Elevated',
                      ),
                    ),
                    HorizontalLine(
                      y: 70,
                      color: const Color(0xFFEF5350).withValues(alpha: 0.25),
                      strokeWidth: 1.5,
                      dashArray: [4, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          color: const Color(0xFFEF5350),
                          fontWeight: FontWeight.w600,
                        ),
                        labelResolver: (line) => 'High Risk',
                      ),
                    ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [
                        AppTheme.kPrimaryDeep,
                        Color(0xFF8B5CF6),
                      ],
                    ),
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: index == spots.length - 1 ? 5 : 3.5,
                          color: Colors.white,
                          strokeWidth: 2,
                          strokeColor: AppTheme.kPrimaryDeep,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.kPrimaryDeep.withValues(alpha: 0.2),
                          const Color(0xFF8B5CF6).withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        String riskLabel = 'Low';
                        if (spot.y > 70) {
                          riskLabel = 'High';
                        } else if (spot.y > 45) {
                          riskLabel = 'Elevated';
                        } else if (spot.y > 20) {
                          riskLabel = 'Moderate';
                        }

                        return LineTooltipItem(
                          'T+${spot.x.toInt()}m\n${spot.y.toStringAsFixed(0)}% ($riskLabel)',
                          GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Widget Builders
  // ─────────────────────────────────────────────────────────────

  Widget _buildServiceStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _isServiceRunning
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: _isServiceRunning
              ? Colors.green.shade200
              : Colors.red.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isServiceRunning ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isServiceRunning
                ? 'Sensor Stream Active'
                : 'Reconnecting Sensors...',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _isServiceRunning
                  ? Colors.green.shade800
                  : Colors.red.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryWarning() {
    return GestureDetector(
      onTap: () => openAppSettings(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.battery_alert_rounded,
                color: Colors.orange.shade700, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Battery optimization may interrupt monitoring. Tap to fix.',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: Colors.orange.shade800),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.orange.shade400, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskCard(double risk, Color riskCol) {
    return AnimatedBuilder(
      animation: _riskPulseController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                riskCol.withValues(alpha: 0.9),
                riskCol.withValues(alpha: 0.65),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: riskCol.withValues(
                    alpha: 0.25 * _riskPulseAnimation.value),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.shield_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Anxiety Risk Score',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        Text(
                          _snapshot.riskLabel,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Score circle
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 2.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        risk.toStringAsFixed(0),
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Risk bar — uses LayoutBuilder for safe animated width
              LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth =
                      constraints.maxWidth * (risk / 100).clamp(0.02, 1.0);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          width: barWidth,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Low',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.7))),
                  Text('Moderate',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.7))),
                  Text('Elevated',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.7))),
                  Text('High',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.7))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdviceCard(double risk) {
    String title = "";
    String advice = "";
    IconData icon = Icons.lightbulb_outline_rounded;
    Color color = Colors.blue;

    // Check if there is an anxiety escalation predicted in the next 10 minutes
    final forecast = _effectiveForecastData;
    final maxForecastedRisk = forecast.isNotEmpty
        ? forecast.map(_scaleForecastValue).reduce(max)
        : 0.0;
    
    final bool isEscalating = maxForecastedRisk > 70.0 && risk <= 70.0;

    if (isEscalating) {
      title = "Anxiety Escalation Predicted";
      advice = "Our predictive model projects a significant rise in your stress levels within the next few minutes. Consider taking a proactive break to practice a grounding exercise now.";
      color = const Color(0xFFFF7043);
      icon = Icons.hourglass_top_rounded;
    } else if (risk <= 20) {
      title = "Feeling Balanced";
      advice = "Your anxiety levels seem to be lowering lately. You appear relaxed and well-rested. Keep up your current routine!";
      color = const Color(0xFF4CAF50);
      icon = Icons.spa_rounded;
    } else if (risk <= 45) {
      title = "Slightly Elevated";
      advice = "Your physiological signals show mild stress. Consider taking a 5-minute break to do some deep breathing.";
      color = const Color(0xFFFFA726);
      icon = Icons.self_improvement_rounded;
    } else if (risk <= 70) {
      title = "Moderate Anxiety Detected";
      advice = "Your metrics indicate elevated stress levels. It might be helpful to step away, hydrate, and practice a grounding exercise.";
      color = const Color(0xFFFF7043);
      icon = Icons.warning_amber_rounded;
    } else {
      title = "High Stress Alert";
      advice = "Your anxiety levels seem to be going higher lately. Please prioritize your well-being right now. Try a guided meditation or reach out to a support system.";
      color = const Color(0xFFEF5350);
      icon = Icons.health_and_safety_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  advice,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppTheme.kTextDark.withValues(alpha: 0.8),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildForecastChart(),
        const SizedBox(height: 28),
        Text(
          '30-Day Physiological Trends',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.kTextDark,
          ),
        ),
        const SizedBox(height: 16),
        _buildSingleChart('Heart Rate (bpm)', _generateMonthlyData(75, 15), const [Color(0xFFFF6B6B), Color(0xFFee5a24)]),
        const SizedBox(height: 16),
        _buildSingleChart('Breathing Rate (br/min)', _generateMonthlyData(16, 4), const [Color(0xFF4facfe), Color(0xFF00f2fe)]),
        const SizedBox(height: 16),
        _buildSingleChart('Body Temperature (°C)', _generateMonthlyData(36.8, 0.4), const [Color(0xFFF6D365), Color(0xFFFDA085)]),
        const SizedBox(height: 16),
        _buildSingleChart('Motion (g)', _generateMonthlyData(0.5, 1.2), const [Color(0xFFA18CD1), Color(0xFFFBC2EB)]),
      ],
    );
  }

  List<FlSpot> _generateMonthlyData(double base, double variance) {
    return List.generate(30, (index) {
      final x = (index + 1).toDouble();
      final noise = (Random().nextDouble() - 0.5) * variance;
      final trend = sin(index / 30 * pi * 2) * (variance * 0.5);
      // Ensure positive values
      return FlSpot(x, max(0.1, base + trend + noise));
    });
  }

  Widget _buildSingleChart(String title, List<FlSpot> data, List<Color> gradient) {
    double minY = data.map((e) => e.y).reduce(min) * 0.9;
    double maxY = data.map((e) => e.y).reduce(max) * 1.1;

    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.kTextLight,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 1,
                maxX: 30,
                minY: minY,
                maxY: maxY,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: data,
                    isCurved: true,
                    gradient: LinearGradient(colors: gradient),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: gradient.map((c) => c.withValues(alpha: 0.2)).toList(),
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          spot.y.toStringAsFixed(1),
                          GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// KPI Card
// ═══════════════════════════════════════════════════════════════════════════════

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final String status;
  final Color statusColor;
  final List<Color> gradient;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.status,
    required this.statusColor,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + status badge
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Value
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  value,
                  key: ValueKey(value),
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.kTextDark,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppTheme.kTextLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Label
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppTheme.kTextLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
