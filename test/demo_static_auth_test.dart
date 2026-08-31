import 'package:anxiety_mobile_app/services/demo_auth_service.dart';
import 'package:anxiety_mobile_app/services/participant_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('static login creates and reuses a participant id', () async {
    final first = await DemoAuthService.login(
      email: DemoAuthService.staticEmail,
      password: DemoAuthService.staticPassword,
    );
    expect(first.isSuccess, isTrue);
    expect(first.account, isNotNull);

    final participantId = first.account!.participantId;
    final validId = ParticipantIdentityService.isParticipantId(participantId);
    expect(validId, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_id'), participantId);

    final second = await DemoAuthService.login(
      email: DemoAuthService.staticEmail,
      password: DemoAuthService.staticPassword,
    );
    expect(second.isSuccess, isTrue);
    expect(second.account!.participantId, participantId);
  });

  test('static login rejects other credentials', () async {
    final result = await DemoAuthService.login(
      email: 'someone@example.com',
      password: 'wrong-password',
    );
    expect(result.isSuccess, isFalse);
  });
}
