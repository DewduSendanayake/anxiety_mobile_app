import 'package:anxiety_mobile_app/services/chest_strap_service.dart';
import 'package:anxiety_mobile_app/services/anxiety_feedback_service.dart';
import 'package:anxiety_mobile_app/services/participant_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('parses the exact 12-field ChestStrap_V3 BLE contract', () {
    final reading = ChestStrapReading.fromCsv(
      '1234,72.0,833.33,46.0,43.0,15.5,0.55,36.6,0.04,1.0,0.018,1',
    );

    expect(reading.timestamp, 1234);
    expect(reading.meanHR, 72.0);
    expect(reading.meanRR, 833.33);
    expect(reading.isWorn, isTrue);
  });

  test(
    'progressive stress profile increases risk in the expected direction',
    () {
      final service = ChestStrapService();
      final calm = service.buildSimulatedReadingForTest(0.0);
      final stressed = service.buildSimulatedReadingForTest(1.0);

      expect(stressed.meanHR, greaterThan(calm.meanHR));
      expect(stressed.meanBR, greaterThan(calm.meanBR));
      expect(stressed.rmssd, lessThan(calm.rmssd));
      expect(stressed.sdnn, lessThan(calm.sdnn));
      expect(stressed.riskScore, greaterThan(calm.riskScore));
      expect(stressed.meanHR, greaterThanOrEqualTo(140.0));
      expect(stressed.meanBR, greaterThanOrEqualTo(35.0));
      expect(stressed.riskScore, greaterThan(90.0));
      expect(stressed.motionStatus, 'High');
    },
  );

  test('participant IDs contain no entered display name', () async {
    SharedPreferences.setMockInitialValues({});

    final participantId = await ParticipantIdentityService.createForDisplayName(
      'Real Person Name',
    );
    final preferences = await SharedPreferences.getInstance();

    expect(ParticipantIdentityService.isParticipantId(participantId), isTrue);
    expect(participantId, isNot(contains('Real')));
    expect(preferences.getString('display_name'), 'Real Person Name');
    expect(preferences.getString('user_id'), participantId);
  });

  test('high-risk alert requires three continuous minutes', () {
    final gate = SustainedHighRiskGate();
    final start = DateTime.utc(2026, 1, 1, 12);

    expect(gate.shouldAlert(75, start), isFalse);
    expect(
      gate.shouldAlert(75, start.add(const Duration(minutes: 2, seconds: 59))),
      isFalse,
    );

    // A single dip breaks continuity and starts a fresh three-minute window.
    expect(
      gate.shouldAlert(69, start.add(const Duration(minutes: 3))),
      isFalse,
    );
    final restartedAt = start.add(const Duration(minutes: 3, seconds: 1));
    expect(gate.shouldAlert(75, restartedAt), isFalse);
    expect(
      gate.shouldAlert(75, restartedAt.add(const Duration(minutes: 3))),
      isTrue,
    );

    // Do not repeat during the same episode. Recovery below 60 rearms it.
    expect(
      gate.shouldAlert(80, restartedAt.add(const Duration(minutes: 4))),
      isFalse,
    );
    expect(
      gate.shouldAlert(55, restartedAt.add(const Duration(minutes: 5))),
      isFalse,
    );
    final secondEpisode = restartedAt.add(const Duration(minutes: 6));
    expect(gate.shouldAlert(75, secondEpisode), isFalse);
    expect(
      gate.shouldAlert(75, secondEpisode.add(const Duration(minutes: 3))),
      isTrue,
    );
  });

  test(
    'simulator publishes worn and off-body packets on the BLE stream',
    () async {
      final service = ChestStrapService();

      final wornPacket = service.readingsStream.first;
      await service.startSimulation(isWorn: true);
      final worn = await wornPacket.timeout(const Duration(seconds: 2));

      expect(service.isConnected, isTrue);
      expect(worn.isWorn, isTrue);
      expect(worn.meanHR, inInclusiveRange(60.0, 90.0));
      expect(worn.meanTemp, inInclusiveRange(36.0, 37.2));

      service.setSimulationStress(true);
      expect(service.simulatedStressIncreasing.value, isTrue);

      final offBodyPacket = service.readingsStream.firstWhere((r) => !r.isWorn);
      service.setSimulationWorn(false);
      final offBody = await offBodyPacket.timeout(const Duration(seconds: 2));

      expect(offBody.meanHR, 0.0);
      expect(offBody.meanRR, 0.0);
      expect(offBody.meanTemp, 0.0);
      expect(service.simulatedStressIncreasing.value, isFalse);

      await service.stopSimulation();
      expect(service.isConnected, isFalse);
      expect(service.lastReading, isNull);
    },
  );
}
