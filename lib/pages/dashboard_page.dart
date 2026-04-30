import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../background_service_helper.dart';
import '../services/notification_helper.dart';
import '../services/rating_settings.dart';
import '../main.dart'; // to access navigatorKey if needed

class DashboardPage extends StatefulWidget {
  final String? userId;
  const DashboardPage({super.key, this.userId});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  String _cachedId = "";
  double _currentPressure = 0.0;
  bool _isPressed = false;
  DateTime? _lastSentAt;

  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;

  @override
  void initState() {
    super.initState();
    _loadCachedId();

    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _breatheAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOutQuad),
    );

    // Setup notification click listener
    NotificationHelper.onNotificationClick = () {
      if (mounted) showRatingDialog();
    };
  }

  @override
  void dispose() {
    _breatheController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedId() async {
    if (widget.userId != null) {
      setState(() => _cachedId = widget.userId!);
    } else {
      String id = await BackgroundServiceHelper.getCachedId();
      if (mounted) setState(() => _cachedId = id);
    }
  }

  Future<void> showRatingDialog() async {
    final prefs = await SharedPreferences.getInstance();
    String uid = prefs.getString('user_id') ?? "Unknown";

    int? selected = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('Daily Check-in'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                children: List.generate(6, (i) {
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, i),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: AppTheme.kBgBottom,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "$i",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );

    if (selected != null) {
      await BackgroundServiceHelper.sendToSheet(
        uid,
        "Stress_Rating",
        selected.toString(),
      );
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await prefs.setString('last_rating_submitted', today);
    }
  }

  void _handleTouch(PointerEvent event, bool isPressed) async {
    setState(() {
      _isPressed = isPressed;
      // Fallback for screens without pressure sensitivity
      _currentPressure = isPressed
          ? (event.pressure == 0 || event.pressure == 1.0
                ? 0.5
                : event.pressure)
          : 0.0;
    });

    if (isPressed) {
      _breatheController.stop();
      final now = DateTime.now();
      bool enoughTime =
          _lastSentAt == null ||
          now.difference(_lastSentAt!) >= const Duration(milliseconds: 300);

      if (enoughTime) {
        _lastSentAt = now;
        await BackgroundServiceHelper.sendToSheet(
          _cachedId,
          "Touch_Event",
          "Pressure:${_currentPressure.toStringAsFixed(2)}",
        );
      }
    } else {
      _breatheController.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.settings_rounded, color: AppTheme.kTextLight),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RatingSettingsPage()),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE0C3FC), Color(0xFF8EC5FC)],
            stops: [0.2, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Text(
                "How are you feeling?",
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Hold the orb to match your anxiety level.",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const Spacer(flex: 3),
              Listener(
                onPointerDown: (e) => _handleTouch(e, true),
                onPointerMove: (e) => _handleTouch(e, true),
                onPointerUp: (e) => _handleTouch(e, false),
                onPointerCancel: (e) => _handleTouch(e, false),
                child: AnimatedBuilder(
                  animation: _breatheController,
                  builder: (context, child) {
                    double scale = _isPressed
                        ? 0.9 + (_currentPressure * 0.3)
                        : _breatheAnimation.value;

                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _isPressed
                                ? [
                                    const Color(0xFFFF9A9E),
                                    const Color(0xFFFECFEF),
                                  ]
                                : [
                                    Colors.white.withOpacity(0.9),
                                    Colors.white.withOpacity(0.4),
                                  ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.4),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                            BoxShadow(
                              color: AppTheme.kPrimaryDeep.withOpacity(0.2),
                              blurRadius: 60,
                              spreadRadius: 5,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            _isPressed ? Icons.favorite : Icons.fingerprint,
                            size: 60,
                            color: _isPressed
                                ? Colors.white
                                : AppTheme.kPrimaryDeep.withOpacity(0.5),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Spacer(flex: 3),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Text(
                  _cachedId.isNotEmpty
                      ? "ID: $_cachedId • Monitoring Active"
                      : "Initializing...",
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
