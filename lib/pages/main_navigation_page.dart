import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../profile_page.dart';
import 'dashboard_page.dart';
import 'digital_phenotyping_page.dart';

class MainNavigationPage extends StatefulWidget {
  final String? userId;
  const MainNavigationPage({super.key, this.userId});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  late AnimationController _cardController;
  late Animation<Offset> _slideLeft;
  late Animation<Offset> _slideRight;
  late Animation<double> _cardFade;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slideLeft = Tween<Offset>(
      begin: const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _cardController,
      curve: const Interval(0.1, 0.8, curve: Curves.easeOutCubic),
    ));
    _slideRight = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _cardController,
      curve: const Interval(0.2, 0.9, curve: Curves.easeOutCubic),
    ));
    _cardFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _cardController,
      curve: const Interval(0.1, 0.7, curve: Curves.easeOut),
    ));

    _fadeController.forward();
    _cardController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  void _navigateToPhysiological() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => DashboardPage(userId: widget.userId),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _navigateToPhenotyping() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) =>
            DigitalPhenotypingPage(userId: widget.userId),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded, color: Colors.white),
            tooltip: 'Profile',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // ── Header ──
                  Text(
                    'Mindful Tracker',
                    style: GoogleFonts.poppins(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose a research module to begin.',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ── Module Cards ──
                  Expanded(
                    child: Column(
                      children: [
                        // Physiological Card
                        SlideTransition(
                          position: _slideLeft,
                          child: FadeTransition(
                            opacity: _cardFade,
                            child: _ModuleCard(
                              title: 'Physiological Monitoring',
                              subtitle:
                                  'Heart rate, breathing, body temperature & motion analysis via wearable sensors.',
                              icon: Icons.monitor_heart_rounded,
                              gradient: const [
                                Color(0xFF667eea),
                                Color(0xFF764ba2),
                              ],
                              accentIcon: Icons.favorite_rounded,
                              onTap: _navigateToPhysiological,
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Digital Phenotyping Card
                        SlideTransition(
                          position: _slideRight,
                          child: FadeTransition(
                            opacity: _cardFade,
                            child: _ModuleCard(
                              title: 'Digital Phenotyping',
                              subtitle:
                                  'Behavioural patterns, app usage, screen time & social interaction signals.',
                              icon: Icons.psychology_rounded,
                              gradient: const [
                                Color(0xFF764ba2),
                                Color(0xFF667eea),
                              ],
                              accentIcon: Icons.bubble_chart_rounded,
                              onTap: _navigateToPhenotyping,
                            ),
                          ),
                        ),

                        const Spacer(),

                        // ── Footer ──
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
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

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Module Card Widget
// ─────────────────────────────────────────────────────────────

class _ModuleCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final IconData accentIcon;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.accentIcon,
    required this.onTap,
  });

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isHovering = true),
      onTapUp: (_) {
        setState(() => _isHovering = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isHovering = false),
      child: AnimatedScale(
        scale: _isHovering ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.gradient,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.gradient.first.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Background accent icon
              Positioned(
                right: -10,
                bottom: -10,
                child: Icon(
                  widget.accentIcon,
                  size: 90,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon circle
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      widget.icon,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Title
                  Text(
                    widget.title,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Subtitle
                  Text(
                    widget.subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Arrow row
                  Row(
                    children: [
                      Text(
                        'Open Module',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
