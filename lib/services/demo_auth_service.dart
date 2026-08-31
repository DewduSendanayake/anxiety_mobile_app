import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'participant_identity_service.dart';

/// Static local-only authentication for the investor demo build.
///
/// This is intentionally not production authentication. There is no remote
/// login endpoint, JWT, refresh token, registration flow, or password policy.
/// A successful login activates one stable pseudonymous participant ID on the
/// device so the existing central-backend enrolment and fusion flow can keep
/// using the same patient identity.
class DemoAuthService {
  static const String staticEmail = 'patient@aura.demo';
  static const String staticPassword = 'Aura1234';
  static const String _displayName = 'Aura Demo Patient';
  static const int _age = 24;

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static Future<DemoAuthResult> login({
    required String email,
    required String password,
  }) async {
    if (normalizeEmail(email) != staticEmail || password != staticPassword) {
      return const DemoAuthResult.failure('Incorrect demo email or password.');
    }

    final prefs = await SharedPreferences.getInstance();
    final storedParticipantId = prefs.getString(
      ParticipantIdentityService.participantIdKey,
    );
    final participantId =
        storedParticipantId != null &&
            ParticipantIdentityService.isParticipantId(storedParticipantId)
        ? storedParticipantId
        : await ParticipantIdentityService.createForDisplayName(_displayName);

    final account = DemoAccount(
      email: staticEmail,
      displayName: _displayName,
      age: _age,
      participantId: participantId,
      createdAt: DateTime.now().toUtc(),
    );

    await _activateAccount(prefs, account);
    return DemoAuthResult.success(account);
  }

  static Future<void> _activateAccount(
    SharedPreferences prefs,
    DemoAccount account,
  ) async {
    await prefs.setString(
      ParticipantIdentityService.participantIdKey,
      account.participantId,
    );
    await prefs.setString(
      ParticipantIdentityService.displayNameKey,
      account.displayName,
    );
    await prefs.setString('user_id', account.participantId);
    await prefs.setString('demo_auth_email', account.email);

    // Keep the existing profile flow intact. The static login only pre-fills
    // age; it does not silently mark the research profile as complete.
    Map<String, dynamic> profile = <String, dynamic>{};
    final rawProfile = prefs.getString('user_profile_data');
    if (rawProfile != null && rawProfile.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProfile);
        if (decoded is Map) {
          profile = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        profile = <String, dynamic>{};
      }
    }
    profile['age'] = account.age.toString();
    await prefs.setString('user_profile_data', jsonEncode(profile));
  }
}

class DemoAccount {
  final String email;
  final String displayName;
  final int age;
  final String participantId;
  final DateTime createdAt;

  const DemoAccount({
    required this.email,
    required this.displayName,
    required this.age,
    required this.participantId,
    required this.createdAt,
  });
}

class DemoAuthResult {
  final DemoAccount? account;
  final String? error;

  const DemoAuthResult._({this.account, this.error});

  const DemoAuthResult.failure(String message)
    : this._(account: null, error: message);

  factory DemoAuthResult.success(DemoAccount account) =>
      DemoAuthResult._(account: account);

  bool get isSuccess => account != null;
}
