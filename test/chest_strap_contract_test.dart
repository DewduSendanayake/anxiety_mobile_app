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

  test('predictive alert requires a rise five or more minutes ahead', () {
    final gate = PredictiveEscalationGate();
    final start = DateTime.utc(2026, 1, 1, 12);

    // A spike only in minutes 1-4 is too late to count as a five-minute
    // early-warning forecast.
    expect(
      gate.evaluate(
        currentRisk: 20,
        riskForecast: [80, 80, 80, 80, 25, 25, 25, 25, 25, 25],
        observedAt: start,
      ),
      isNull,
    );

    const risingForecast = <double>[25, 30, 35, 40, 48, 55, 62, 72, 78, 80];
    // One forecast is not enough; a second independent poll confirms the
    // trend without sacrificing the five-minute lead window.
    expect(
      gate.evaluate(
        currentRisk: 25,
        riskForecast: risingForecast,
        observedAt: start.add(const Duration(seconds: 30)),
      ),
      isNull,
    );
    final escalation = gate.evaluate(
      currentRisk: 25,
      riskForecast: risingForecast,
      observedAt: start.add(const Duration(seconds: 60)),
    );
    expect(escalation, isNotNull);
    expect(escalation!.leadMinutes, greaterThanOrEqualTo(5));
    expect(escalation.predictedPeakRisk, 80);
    expect(escalation.increase, 55);

    // Do not repeat during the same episode.
    expect(
      gate.evaluate(
        currentRisk: 28,
        riskForecast: risingForecast,
        observedAt: start.add(const Duration(seconds: 90)),
      ),
      isNull,
    );

    // Low current and future risk re-arm the gate for a later episode.
    expect(
      gate.evaluate(
        currentRisk: 18,
        riskForecast: const [18, 18, 20, 20, 22, 22, 23, 23, 24, 24],
        observedAt: start.add(const Duration(minutes: 2)),
      ),
      isNull,
    );
    expect(
      gate.evaluate(
        currentRisk: 25,
        riskForecast: risingForecast,
        observedAt: start.add(const Duration(minutes: 2, seconds: 30)),
      ),
      isNull,
    );
    expect(
      gate.evaluate(
        currentRisk: 25,
        riskForecast: risingForecast,
        observedAt: start.add(const Duration(minutes: 3)),
      ),
      isNotNull,
    );
  });

  test('predictive alert does not reuse a stale confirmation', () {
    final gate = PredictiveEscalationGate();
    final start = DateTime.utc(2026, 1, 1, 12);
    const risingForecast = <double>[25, 30, 35, 40, 48, 55, 62, 72, 78, 80];

    expect(
      gate.evaluate(
        currentRisk: 25,
        riskForecast: risingForecast,
        observedAt: start,
      ),
      isNull,
    );
    expect(
      gate.evaluate(
        currentRisk: 25,
        riskForecast: risingForecast,
        observedAt: start.add(const Duration(minutes: 5)),
      ),
      isNull,
    );
    expect(
      gate.evaluate(
        currentRisk: 25,
        riskForecast: risingForecast,
        observedAt: start.add(const Duration(minutes: 5, seconds: 30)),
      ),
      isNotNull,
    );
  });

  test('predictive gate can retry after notification delivery fails', () {
    final gate = PredictiveEscalationGate();
    final start = DateTime.utc(2026, 1, 1, 12);
    const risingForecast = <double>[25, 30, 35, 40, 48, 55, 62, 72, 78, 80];

    gate.evaluate(
      currentRisk: 25,
      riskForecast: risingForecast,
      observedAt: start,
    );
    expect(
      gate.evaluate(
        currentRisk: 25,
        riskForecast: risingForecast,
        observedAt: start.add(const Duration(seconds: 30)),
      ),
      isNotNull,
    );

    gate.allowRetry();
    expect(
      gate.evaluate(
        currentRisk: 25,
        riskForecast: risingForecast,
        observedAt: start.add(const Duration(minutes: 1)),
      ),
      isNull,
    );
    expect(
      gate.evaluate(
        currentRisk: 25,
        riskForecast: risingForecast,
        observedAt: start.add(const Duration(minutes: 1, seconds: 30)),
      ),
      isNotNull,
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
