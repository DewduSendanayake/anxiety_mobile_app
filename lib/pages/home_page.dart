import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/chest_strap_service.dart';

/// Home Page — the first tab the user sees.
///
/// Displays:
///   • Aura branding & subtitle
///   • Meditation hero image (from assets)
///   • Overall anxiety status card (combined physiological + phenotyping risk)
///   • Notification bell for anxiety escalation alerts
class HomePage extends StatefulWidget {
  final String? userId;
  const HomePage({super.key, this.userId});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with TickerProviderStateMixin {
  // ── Chest Strap Service ──────────────────────────────────────
  final ChestStrapService _chestStrap = ChestStrapService();
  ChestStrapReading? _lastReading;

  // ── Phenotyping risk (static simulation) ────────────────────
  static const double _phenotypingRisk = 0.72; // from GATv2

  // ── Notification state ─────────────────────────────────────
  final List<String> _notifications = [];
  bool _hasUnread = false;

  // ── Animation ──────────────────────────────────────────────
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to real chest strap data
    _lastReading = _chestStrap.lastReading; // Load persisted reading
    _chestStrap.onDataReceived = (reading) {
      if (mounted) {
        final oldLabel = _overallLabel(_lastReading);
        setState(() => _lastReading = reading);
        final newLabel = _overallLabel(reading);
        if (_isEscalation(oldLabel, newLabel)) {
          _addNotification(
            'Anxiety escalation detected — your risk level changed from $oldLabel to $newLabel.',
          );
        }
      }
    };

    // Listen for connection state changes so the UI updates when the
    // chest strap connects or disconnects.
    _chestStrap.connectionState.addListener(_onConnectionChanged);
  }

  void _onConnectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _chestStrap.connectionState.removeListener(_onConnectionChanged);
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Combined Risk Logic ─────────────────────────────────────
  /// Combines physiological risk (0-100) and phenotyping risk (0.0-1.0)
  /// into an overall normalised score (0-100).
  double get _overallRisk {
    final physioNorm = _lastReading?.riskScore ?? 0.0;
    final phenoNorm = _phenotypingRisk * 100;
    return (physioNorm * 0.75 + phenoNorm * 0.25).clamp(0, 100);
  }

  String _overallLabel(ChestStrapReading? reading) {
    final score = reading?.riskScore ?? 0.0;
    final combined = (score * 0.75 + _phenotypingRisk * 100 * 0.25).clamp(0, 100);
    if (combined <= 25) return 'Low';
    if (combined <= 50) return 'Moderate';
    if (combined <= 75) return 'Elevated';
    return 'High';
  }

  Color _overallColor(double score) {
    if (score <= 25) return const Color(0xFF4CAF50);
    if (score <= 50) return const Color(0xFFFFA726);
    if (score <= 75) return const Color(0xFFFF7043);
    return const Color(0xFFEF5350);
  }

  IconData _overallIcon(double score) {
    if (score <= 25) return Icons.sentiment_very_satisfied_rounded;
    if (score <= 50) return Icons.sentiment_satisfied_rounded;
    if (score <= 75) return Icons.sentiment_neutral_rounded;
    return Icons.sentiment_very_dissatisfied_rounded;
  }

  String _overallMessage(double score) {
    if (score <= 25) {
      return 'Your overall anxiety score is currently low. You\'re doing great — keep it up! 🌿';
    } else if (score <= 50) {
      return 'Your anxiety level is moderate. Consider taking a moment to breathe and relax. 🧘';
    } else if (score <= 75) {
      return 'Your anxiety appears elevated. Try a short break or a calming activity. 💙';
    } else {
      return 'Your anxiety level is high. Please prioritize self-care and reach out for support if needed. ❤️';
    }
  }

  bool _isEscalation(String oldLabel, String newLabel) {
    const levels = ['Low', 'Moderate', 'Elevated', 'High'];
    final oldIdx = levels.indexOf(oldLabel);
    final newIdx = levels.indexOf(newLabel);
    return newIdx > oldIdx;
  }

  void _addNotification(String msg) {
    setState(() {
      _notifications.insert(0, msg);
      _hasUnread = true;
    });
  }

  void _showNotifications() {
    setState(() => _hasUnread = false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsSheet(notifications: _notifications),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final risk = _overallRisk;
    final riskCol = _overallColor(risk);
    final label = _overallLabel(_lastReading);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // ── Header Row with Notification Bell ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aura',
                            style: GoogleFonts.poppins(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Track your inner world and find balance.',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      // Notification Bell
                      Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.notifications_outlined,
                                color: Colors.white,
                                size: 26,
                              ),
                              onPressed: _showNotifications,
                              tooltip: 'Anxiety Alerts',
                            ),
                          ),
                          if (_hasUnread)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF4444),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF667eea),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),

                  // ── Connection Status ──
                  if (!_chestStrap.isConnected)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bluetooth_disabled_rounded, color: Colors.white.withValues(alpha: 0.7), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lastReading != null
                                  ? 'Chest strap disconnected — showing last known data'
                                  : 'Chest strap not connected — using model estimates',
                              style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 28),

                  // ── Meditation Hero Image ──
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 260),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/welcome_illustration.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Overall Anxiety Score Card ──
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: riskCol.withValues(
                                  alpha: 0.15 * _pulseAnimation.value),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Risk indicator row
                            Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: riskCol.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: riskCol.withValues(alpha: 0.4),
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    _overallIcon(risk),
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Overall Anxiety Level',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.white
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        label,
                                        style: GoogleFonts.poppins(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Score circle
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.15),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.4),
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      risk.toStringAsFixed(0),
                                      style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Risk progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Stack(
                                children: [
                                  Container(
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  AnimatedFractionallySizedBox(
                                    duration: const Duration(milliseconds: 600),
                                    widthFactor: (risk / 100).clamp(0.02, 1.0),
                                    child: Container(
                                      height: 6,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white
                                                .withValues(alpha: 0.9),
                                            riskCol.withValues(alpha: 0.8),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _riskLabel('Low', risk <= 25),
                                _riskLabel('Moderate', risk > 25 && risk <= 50),
                                _riskLabel('Elevated', risk > 50 && risk <= 75),
                                _riskLabel('High', risk > 75),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Message
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Text(
                                _overallMessage(risk),
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),

                            const SizedBox(height: 12),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // ── Quick Tips Card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          color: Colors.white.withValues(alpha: 0.7),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'All data is encrypted and anonymised for research purposes only.',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Helper widgets ─────────────────────────────────────────────

  Widget _riskLabel(String text, bool active) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 10,
        color: Colors.white.withValues(alpha: active ? 1.0 : 0.5),
        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Notifications Sheet
// ═════════════════════════════════════════════════════════════════════

class _NotificationsSheet extends StatelessWidget {
  final List<String> notifications;
  const _NotificationsSheet({required this.notifications});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667eea).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.notifications_rounded,
                    color: Color(0xFF667eea),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Anxiety Alerts',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2D3142),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${notifications.length}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: notifications.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none_rounded,
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          'No alerts yet',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You\'ll be notified here when anxiety escalations are predicted.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: notifications.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.orange.shade200,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange.shade700, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                notifications[i],
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.orange.shade900,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
