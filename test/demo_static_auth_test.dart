import 'package:anxiety_mobile_app/services/demo_auth_service.dart';
import 'package:anxiety_mobile_app/services/participant_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('static demo login creates and then reuses one participant identity', () async {
    final first = await DemoAuthService.login(
      email: DemoAuthService.staticEmail,
      password: DemoAuthService.staticPassword,
    );

    expect(first.isSuccess, isTrue);
    expect(first.account, isNotNull);
    expect(
      ParticipantIdentityService.isParticipantId(first.account!.participantId),
      isTrue,
    );

    final firstParticipantId = first.account!.participantId;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_id'), firstParticipantId);

    final second = await DemoAuthService.login(
      email: DemoAuthService.staticEmail,
      password: DemoAuthService.staticPassword,
    );

    expect(second.isSuccess, isTrue);
    expect(second.account!.participantId, firstParticipantId);
  });

  test('static demo login rejects any other credentials', () async {
    final result = await DemoAuthService.login(
      email: 'someone@example.com',
      password: 'wrong-password',
    );

    expect(result.isSuccess, isFalse);
  });
}
