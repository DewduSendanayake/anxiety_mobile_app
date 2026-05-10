import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../background_service_helper.dart';
import '../services/notification_helper.dart';
import '../services/rating_settings.dart';
import '../services/physio_simulator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../ema_and_gad7.dart';
import '../profile_page.dart';

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

    // Notification click handler
    NotificationHelper.onNotificationClick = (payload) {
      if (mounted) {
        if (payload != null && payload.startsWith('ema_rating_')) {
          final period = payload.replaceFirst('ema_rating_', '');
          _showEmaSheet(period);
        } else if (payload == 'gad7_weekly') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const Gad7Screen()),
          );
        } else if (payload == 'pss10_monthly') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const Pss10Screen()),
          );
        }
      }
    };

    _startStatusCheck();
  }

  @override
  void dispose() {
    _simulator.stop();
    _riskPulseController.dispose();
    _entryController.dispose();
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
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.kTextDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            children: [
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

              // ── Quick Assessments ──
              _buildAssessmentSection(),

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
          ),
        ),
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

              // Risk bar
              ClipRRect(
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
                    AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      widthFactor: (risk / 100).clamp(0.02, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
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

  Widget _buildAssessmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Assessments',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.kTextDark,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _AssessmentChip(
                label: 'GAD-7',
                subtitle: 'Anxiety',
                icon: Icons.assignment_outlined,
                color: const Color(0xFF5E60CE),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const Gad7Screen()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AssessmentChip(
                label: 'PSS-10',
                subtitle: 'Stress',
                icon: Icons.psychology_outlined,
                color: const Color(0xFF4facfe),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const Pss10Screen()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AssessmentChip(
                label: 'EMA',
                subtitle: 'Check-in',
                icon: Icons.emoji_emotions_outlined,
                color: const Color(0xFFFFA726),
                onTap: () => _showEmaSheet('afternoon'),
              ),
            ),
          ],
        ),
      ],
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

// ═══════════════════════════════════════════════════════════════════════════════
// Assessment Chip
// ═══════════════════════════════════════════════════════════════════════════════

class _AssessmentChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AssessmentChip({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.kTextDark,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: AppTheme.kTextLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
