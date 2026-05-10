import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../profile_page.dart';
import '../services/rating_settings.dart';

class DigitalPhenotypingPage extends StatelessWidget {
  final String? userId;
  const DigitalPhenotypingPage({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Digital Phenotyping',
          style: GoogleFonts.poppins(
            color: AppTheme.kTextDark,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded, color: AppTheme.kTextDark),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: AppTheme.kTextDark),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RatingSettingsPage()),
            ),
          ),
          const SizedBox(width: 8),
        ],
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
          child: Center(
            child: Text(
              'Digital Phenotyping Dashboard\n(Coming Soon)',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
