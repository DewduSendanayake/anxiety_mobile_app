import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background_service.dart';
import '../profile_page.dart';
import '../services/api_service.dart';
import '../services/demo_auth_service.dart';
import '../services/participant_identity_service.dart';
import '../services/user_manager.dart';
import '../theme/app_theme.dart';
import 'baseline_calibration_page.dart';
import 'informed_consent_page.dart';
import 'main_navigation_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController(
    text: DemoAuthService.staticEmail,
  );
  final _passwordController = TextEditingController(
    text: DemoAuthService.staticPassword,
  );

  bool _passwordVisible = false;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (_submitting) return;

    setState(() => _submitting = true);
    try {
      final result = await DemoAuthService.login(
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;
      if (!result.isSuccess) {
        _showError(result.error ?? 'Could not log in.');
        return;
      }

      final account = result.account!;
      await _selfEnrolParticipant(account.participantId);
      UserManager().login(account.participantId);
      await _startCollectionIfPossible();

      final prefs = await SharedPreferences.getInstance();
      final profileComplete = prefs.getBool('profile_complete') ?? false;
      final calibrationComplete =
          prefs.getBool('calibration_complete') ?? false;

      if (!mounted) return;
      final Widget destination;
      if (!profileComplete) {
        destination = const ProfilePage();
      } else if (!calibrationComplete) {
        destination = BaselineCalibrationPage(userId: account.participantId);
      } else {
        destination = MainNavigationPage(userId: account.participantId);
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => destination),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _selfEnrolParticipant(String participantId) async {
    final subjectId = await ApiService.selfEnrol(participantId);
    if (subjectId != null && subjectId.isNotEmpty) {
      await ParticipantIdentityService.saveCentralSubjectId(subjectId);
    }
  }

  Future<void> _startCollectionIfPossible() async {
    if (kIsWeb) return;
    try {
      await startBackgroundServiceIfPermitted();
    } catch (e) {
      debugPrint('Background service start deferred after demo auth: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF111218), Color(0xFF1A1B24)]
                : const [AppTheme.kBgTop, AppTheme.kBgBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    _buildLogo(),
                    const SizedBox(height: 18),
                    Text(
                      'Welcome to Aura',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Investor demo login',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        height: 1.45,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _loginCard(),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 17,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Temporary static login for the investor demo. '
                              'No backend authentication, signup validation, JWT, '
                              'or remote account service is used. The device keeps '
                              'one stable pseudonymous Participant ID for the '
                              'existing research and fusion flow.',
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                height: 1.45,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const InformedConsentPage(readOnly: true),
                          ),
                        );
                      },
                      child: const Text('Review Informed Consent & Privacy'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _emailController,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            style: GoogleFonts.poppins(fontSize: 13.5),
            decoration: _inputDecoration(
              'Email',
              DemoAuthService.staticEmail,
              Icons.email_outlined,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            enabled: !_submitting,
            obscureText: !_passwordVisible,
            onSubmitted: (_) => _submitLogin(),
            style: GoogleFonts.poppins(fontSize: 13.5),
            decoration: _inputDecoration(
              'Password',
              DemoAuthService.staticPassword,
              Icons.lock_outline_rounded,
            ).copyWith(
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _passwordVisible = !_passwordVisible);
                },
                icon: Icon(
                  _passwordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submitLogin,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                _submitting ? 'Please wait…' : 'Log in',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.kPrimaryDeep,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.kPrimaryDeep.withValues(
                  alpha: 0.55,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label,
    String hint,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.52),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppTheme.kPrimaryDeep,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.kPrimaryDeep.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.spa_rounded,
        size: 38,
        color: AppTheme.kPrimaryDeep,
      ),
    );
  }
}
