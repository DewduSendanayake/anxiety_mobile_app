import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

import '../theme/app_theme.dart';
import '../background_service_helper.dart';
import '../services/chest_strap_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../ema_and_gad7.dart';
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
  bool _chestStrapConnected = false;
  bool _isBluetoothReady = false;

  // ── Prediction Pipeline State ──────────────────────────────
  String _predictionStatus = "loading"; // "loading", "buffering", "not_calibrated", "success", "error"
  List<double> _forecastData = [];
  String _statusMessage = "";
  Timer? _predictionTimer;
  int _bufferingCountdown = 60;
  Timer? _bufferingTimer;
  double? _fusionRiskScore; // final score returned by the teammate's fusion model

  // ── Chest Strap Live Data ──────────────────────────────────
  ChestStrapReading? _currentReading;

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

    // Load persisted last reading
    _currentReading = ChestStrapService().lastReading;

    // Listen for live chest strap data
    ChestStrapService().onDataReceived = (reading) {
      if (mounted) {
        setState(() => _currentReading = reading);
        _uploadChestStrapData(reading);
      }
    };

    // Listen for connection state changes to update UI
    ChestStrapService().connectionState.addListener(_onConnectionChanged);

    _startStatusCheck();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBluetoothConnection();
    });
  }

  void _onConnectionChanged() {
    if (mounted) {
      setState(() {
        _chestStrapConnected = ChestStrapService().isConnected;
      });
    }
  }

  @override
  void dispose() {
    ChestStrapService().connectionState.removeListener(_onConnectionChanged);
    _riskPulseController.dispose();
    _entryController.dispose();
    _predictionTimer?.cancel();
    _bufferingTimer?.cancel();
    super.dispose();
  }

  // ── Chest Strap Bluetooth Flow ───────────────────────────────

  // ── Chest Strap Bluetooth Flow ───────────────────────────────

  Future<void> _checkBluetoothConnection() async {
    // Check if Bluetooth adapter is on
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _showBluetoothOffDialog();
      return;
    }

    // Check permissions
    bool scanGranted = await Permission.bluetoothScan.isGranted;
    bool connectGranted = await Permission.bluetoothConnect.isGranted;

    if (!scanGranted || !connectGranted) {
      _showBluetoothPrompt();
    } else {
      // Permissions granted, Bluetooth is ON
      setState(() {
        _isBluetoothReady = true;
      });
    }
  }

  void _showBluetoothOffDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Bluetooth is Off', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'Please turn on Bluetooth to connect your chest strap for real-time anxiety monitoring.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isBluetoothReady = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Using saved data / model weights for risk assessment.')),
              );
            },
            child: Text('Skip', style: GoogleFonts.poppins(color: Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
              Future.delayed(const Duration(seconds: 2), _checkBluetoothConnection);
            },
            child: Text('Turn On', style: GoogleFonts.poppins(color: AppTheme.kPrimaryDeep)),
          ),
        ],
      ),
    );
  }

  void _showBluetoothPrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Connect Chest Strap', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'Aura needs Bluetooth permission to connect to your ChestStrap_V3 for real-time physiological monitoring.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isBluetoothReady = false;
              });
              _showDenyWarning();
            },
            child: Text('Deny', style: GoogleFonts.poppins(color: Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Permission.bluetoothScan.request();
              await Permission.bluetoothConnect.request();
              bool scanOk = await Permission.bluetoothScan.isGranted;
              bool connectOk = await Permission.bluetoothConnect.isGranted;
              if (scanOk && connectOk) {
                setState(() {
                  _isBluetoothReady = true;
                });
              } else {
                setState(() {
                  _isBluetoothReady = false;
                });
                _showDenyWarning();
              }
            },
            child: Text('Allow', style: GoogleFonts.poppins(color: AppTheme.kPrimaryDeep)),
          ),
        ],
      ),
    );
  }

  void _showDenyWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Are you sure?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'Without the chest strap, we can\'t measure your vitals in real-time. The app will use your previous data or global model weights instead.\n\nIs that okay?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showAskAgainPrompt();
            },
            child: Text('No, go back', style: GoogleFonts.poppins(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Using saved data / model weights for risk assessment.')),
              );
            },
            child: Text('Yes, that\'s fine', style: GoogleFonts.poppins(color: AppTheme.kPrimaryDeep)),
          ),
        ],
      ),
    );
  }

  void _showAskAgainPrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Bluetooth Needed', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'To get the best results, please let us use Bluetooth to connect to your ChestStrap_V3.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Using saved data / model weights.')),
              );
            },
            child: Text('Skip', style: GoogleFonts.poppins(color: Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
              Future.delayed(const Duration(seconds: 2), _checkBluetoothConnection);
            },
            child: Text('Turn on Bluetooth', style: GoogleFonts.poppins(color: AppTheme.kPrimaryDeep)),
          ),
        ],
      ),
    );
  }

  void _startChestStrapScan() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scanning for ChestStrap_V3... Please wait.')),
    );
    ChestStrapService().startScan().then((_) {
      if (!mounted) return;
      if (ChestStrapService().isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ ChestStrap_V3 connected successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find ChestStrap_V3. Make sure it is powered on and advertising.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }

  Future<void> _disconnectChestStrap() async {
    await ChestStrapService().disconnect();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chest strap disconnected.')),
      );
    }
  }

  Widget _buildConnectionControlCard() {
    return Container(
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _chestStrapConnected
                  ? const Color(0xFFE8F5E9)
                  : (_isBluetoothReady ? const Color(0xFFE3F2FD) : const Color(0xFFFFEBEE)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _chestStrapConnected
                  ? Icons.bluetooth_connected_rounded
                  : (_isBluetoothReady ? Icons.bluetooth_audio_rounded : Icons.bluetooth_disabled_rounded),
              color: _chestStrapConnected
                  ? Colors.green.shade700
                  : (_isBluetoothReady ? Colors.blue.shade700 : Colors.red.shade700),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _chestStrapConnected
                      ? 'Strap Connected'
                      : (_isBluetoothReady ? 'Bluetooth Ready' : 'Strap Disconnected'),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.kTextDark,
                  ),
                ),
                Text(
                  _chestStrapConnected
                      ? 'ChestStrap_V3 is streaming vital parameters'
                      : (_isBluetoothReady ? 'Tap Connect to pair ChestStrap_V3' : 'Please enable Bluetooth & permissions'),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppTheme.kTextLight,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (_chestStrapConnected) {
                _disconnectChestStrap();
              } else if (_isBluetoothReady) {
                _startChestStrapScan();
              } else {
                _checkBluetoothConnection();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _chestStrapConnected
                  ? Colors.grey.shade100
                  : (_isBluetoothReady ? AppTheme.kPrimaryDeep : Colors.red.shade600),
              foregroundColor: _chestStrapConnected
                  ? AppTheme.kTextDark
                  : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              _chestStrapConnected
                  ? 'Disconnect'
                  : (_isBluetoothReady ? 'Connect' : 'Enable'),
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
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

      // ── Send trajectory to fusion model (fire-and-forget) ──────────────
      // Compute a single physiological risk score = peak scaled value in the
      // 10-step forecast. The fusion teammate uses this number + the full
      // trajectory array to assign a weight and produce a final risk decision.
      if (parsedForecast.isNotEmpty && _cachedId.isNotEmpty) {
        final double peakRisk = parsedForecast
            .map(_scaleForecastValue)
            .reduce((a, b) => a > b ? a : b);
        ApiService.sendToFusionModel(
          userId: _cachedId,
          trajectory: parsedForecast,
          physiologicalRiskScore: peakRisk,
        ).then((fusionResult) {
          if (fusionResult['success'] == true && mounted) {
            setState(() {
              // Store whatever holistic score the fusion model returns
              // (key name TBC with teammate — defaulting to 'final_risk_score')
              _fusionRiskScore = (fusionResult['final_risk_score'] as num?)?.toDouble();
            });
          }
        });
      }
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
    // No real data available yet
    return [];
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

  Future<void> _uploadChestStrapData(ChestStrapReading reading) async {
    if (_cachedId.isEmpty) return;
    final data = {
      'mean_HR': reading.meanHR.toStringAsFixed(1),
      'mean_RR': reading.meanRR.toStringAsFixed(2),
      'SDNN': reading.sdnn.toStringAsFixed(2),
      'RMSSD': reading.rmssd.toStringAsFixed(2),
      'mean_BR': reading.meanBR.toStringAsFixed(1),
      'std_BR': reading.stdBR.toStringAsFixed(2),
      'mean_temp': reading.meanTemp.toStringAsFixed(2),
      'std_temp': reading.stdTemp.toStringAsFixed(2),
      'mean_acc_mag': reading.meanAccMag.toStringAsFixed(4),
      'std_acc_mag': reading.stdAccMag.toStringAsFixed(4),
      'risk_score': reading.riskScore.toStringAsFixed(1),
      'risk_label': reading.riskLabel,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await BackgroundServiceHelper.sendToSheet(
      _cachedId,
      'ChestStrap_Vitals',
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
    final risk = _currentReading?.riskScore ?? 0.0;
    final riskCol = _riskColor(risk);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Vitals Monitor',
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
    return _buildDashboardList(risk, riskCol);
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

        const SizedBox(height: 12),
        _buildConnectionControlCard(),

        if (_predictionStatus == 'not_calibrated') ...[
          const SizedBox(height: 12),
          _buildCalibrationRequiredBanner(),
        ],

        if (_predictionStatus == 'buffering') ...[
          const SizedBox(height: 12),
          _buildBufferingBanner(),
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
                value: _currentReading?.meanHR.toStringAsFixed(0) ?? '--',
                unit: 'bpm',
                icon: Icons.monitor_heart_rounded,
                status: _currentReading?.hrStatus ?? 'N/A',
                statusColor: _statusColor(_currentReading?.hrStatus ?? 'N/A'),
                gradient: const [Color(0xFFFF6B6B), Color(0xFFee5a24)],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _KpiCard(
                label: 'Breathing',
                value: _currentReading?.meanBR.toStringAsFixed(0) ?? '--',
                unit: 'br/min',
                icon: Icons.air_rounded,
                status: _currentReading?.brStatus ?? 'N/A',
                statusColor: _statusColor(_currentReading?.brStatus ?? 'N/A'),
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
                value: _currentReading?.meanTemp.toStringAsFixed(1) ?? '--',
                unit: '°C',
                icon: Icons.thermostat_rounded,
                status: _currentReading?.tempStatus ?? 'N/A',
                statusColor: _statusColor(_currentReading?.tempStatus ?? 'N/A'),
                gradient: const [Color(0xFFF6D365), Color(0xFFFDA085)],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _KpiCard(
                label: 'HRV (RMSSD)',
                value: _currentReading?.rmssd.toStringAsFixed(1) ?? '--',
                unit: 'ms',
                icon: Icons.favorite_border_rounded,
                status: _currentReading?.hrvStatus ?? 'N/A',
                statusColor: _statusColor(_currentReading?.hrvStatus ?? 'N/A'),
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
              'Server offline. Showing last known data. Connect chest strap for live monitoring.',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: Colors.amber.shade800, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildCalibrationRequiredBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD54F)),
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
                decoration: const BoxDecoration(
                  color: Color(0xFFFFECB3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.tune_rounded, color: Color(0xFFFF8F00), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Baseline Calibration Required',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE65100),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'To get accurate predictive anxiety forecasting, Aura needs to record your resting baseline. Please perform a 3-minute resting calibration.',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              color: const Color(0xFFEF6C00),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
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
              backgroundColor: const Color(0xFFFF8F00),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(
              'Start Calibration',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBufferingBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Establishing prediction stream... Buffering initial samples (${_bufferingCountdown}s remaining).',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.blue.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastChart() {
    final List<double> forecast = _effectiveForecastData;
    if (forecast.isEmpty) {
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
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.kPrimaryDeep.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.trending_up_rounded, color: AppTheme.kPrimaryDeep, size: 20),
                ),
                const SizedBox(width: 12),
                Text('10-Minute Anxiety Forecast', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.kTextDark)),
              ],
            ),
            const SizedBox(height: 40),
            Icon(Icons.hourglass_empty_rounded, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Awaiting sensor data...', style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.kTextLight)),
            Text('Forecast will appear after first data window', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade400)),
            const SizedBox(height: 40),
          ],
        ),
      );
    }
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
        color: _chestStrapConnected
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: _chestStrapConnected
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
              color: _chestStrapConnected ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _chestStrapConnected
                ? 'ChestStrap_V3 Connected'
                : 'Chest Strap Disconnected',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _chestStrapConnected
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
                          _currentReading?.riskLabel ?? '--',
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
        ? forecast.map(_scaleForecastValue).reduce((a, b) => a > b ? a : b)
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
        _buildNoHistoryPlaceholder(),
      ],
    );
  }

  Widget _buildNoHistoryPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(24),
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
        children: [
          Icon(Icons.show_chart_rounded, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Historical trends will appear here',
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.kTextLight),
          ),
          const SizedBox(height: 4),
          Text(
            'Keep using Aura with your chest strap to build your physiological history.',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade400),
            textAlign: TextAlign.center,
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
