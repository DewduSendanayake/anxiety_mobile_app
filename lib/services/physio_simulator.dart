import 'dart:async';
import 'dart:math';

/// Simulates real-time physiological data from a wearable chest strap sensor.
///
/// In production this class should be replaced with an actual BLE data stream
/// from the ESP32-C3 chest strap. The simulated values are designed to stay
/// within clinically plausible ranges and occasionally drift into elevated
/// zones so the risk-score logic can be visually demonstrated.
class PhysioSimulator {
  final _rng = Random();
  Timer? _timer;

  // ── Current readings ──────────────────────────────────────────
  double heartRate = 72;
  double breathingRate = 16;
  double bodyTemp = 36.6;
  double motionMagnitude = 0.3; // g-force magnitude (1g = stationary)

  // ── Callbacks ─────────────────────────────────────────────────
  void Function(PhysioSnapshot)? onData;

  /// Start emitting simulated data every [interval].
  void start({Duration interval = const Duration(seconds: 2)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
    // Emit an initial value immediately.
    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  // ── Internal ──────────────────────────────────────────────────

  void _tick() {
    // Smoothly drift each metric toward a random attractor,
    // with occasional "anxiety spike" episodes (~10 % of ticks).
    final bool spike = _rng.nextDouble() < 0.10;

    heartRate = _drift(heartRate, spike ? 105 : 72, spike ? 6 : 2, 50, 140);
    breathingRate =
        _drift(breathingRate, spike ? 24 : 16, spike ? 2.5 : 0.8, 10, 35);
    bodyTemp = _drift(bodyTemp, spike ? 37.3 : 36.6, spike ? 0.15 : 0.05, 35.5, 38.5);
    motionMagnitude =
        _drift(motionMagnitude, spike ? 2.5 : 0.3, spike ? 0.8 : 0.15, 0.0, 5.0);

    onData?.call(snapshot);
  }

  double _drift(
      double current, double attractor, double maxStep, double lo, double hi) {
    final delta = (attractor - current) * 0.15 +
        (_rng.nextDouble() - 0.5) * maxStep;
    return (current + delta).clamp(lo, hi);
  }

  PhysioSnapshot get snapshot => PhysioSnapshot(
        heartRate: heartRate,
        breathingRate: breathingRate,
        bodyTemp: bodyTemp,
        motionMagnitude: motionMagnitude,
      );
}

/// Immutable snapshot of physiological readings at a point in time.
class PhysioSnapshot {
  final double heartRate;
  final double breathingRate;
  final double bodyTemp;
  final double motionMagnitude;

  const PhysioSnapshot({
    required this.heartRate,
    required this.breathingRate,
    required this.bodyTemp,
    required this.motionMagnitude,
  });

  // ── Risk Score ────────────────────────────────────────────────
  // Normalised 0-100 anxiety risk score based on physiological indicators.
  //
  // Factors (clinically informed thresholds for anxiety):
  //   • Heart rate:  resting HR > 90 bpm elevates risk
  //   • Breathing:   > 20 breaths/min elevates risk
  //   • Temperature: deviation from 36.5-37.0 °C elevates risk
  //   • Motion:      restlessness (high g-force) elevates risk
  //
  // Each factor contributes a weighted sub-score.

  double get riskScore {
    // Heart rate sub-score (weight 35 %)
    double hrScore;
    if (heartRate <= 70) {
      hrScore = 0;
    } else if (heartRate <= 90) {
      hrScore = (heartRate - 70) / 20 * 40; // 0-40
    } else if (heartRate <= 110) {
      hrScore = 40 + (heartRate - 90) / 20 * 40; // 40-80
    } else {
      hrScore = 80 + (heartRate - 110).clamp(0, 30) / 30 * 20; // 80-100
    }

    // Breathing rate sub-score (weight 25 %)
    double brScore;
    if (breathingRate <= 16) {
      brScore = 0;
    } else if (breathingRate <= 20) {
      brScore = (breathingRate - 16) / 4 * 40;
    } else if (breathingRate <= 26) {
      brScore = 40 + (breathingRate - 20) / 6 * 40;
    } else {
      brScore = 80 + (breathingRate - 26).clamp(0, 10) / 10 * 20;
    }

    // Temperature sub-score (weight 15 %)
    double tempDeviation = (bodyTemp - 36.75).abs();
    double tempScore;
    if (tempDeviation <= 0.3) {
      tempScore = 0;
    } else if (tempDeviation <= 0.6) {
      tempScore = (tempDeviation - 0.3) / 0.3 * 50;
    } else {
      tempScore = 50 + (tempDeviation - 0.6).clamp(0, 1.0) / 1.0 * 50;
    }

    // Motion sub-score (weight 25 %)
    double motionScore;
    if (motionMagnitude <= 0.5) {
      motionScore = 0;
    } else if (motionMagnitude <= 1.5) {
      motionScore = (motionMagnitude - 0.5) / 1.0 * 40;
    } else if (motionMagnitude <= 3.0) {
      motionScore = 40 + (motionMagnitude - 1.5) / 1.5 * 40;
    } else {
      motionScore = 80 + (motionMagnitude - 3.0).clamp(0, 2.0) / 2.0 * 20;
    }

    return (hrScore * 0.35 +
            brScore * 0.25 +
            tempScore * 0.15 +
            motionScore * 0.25)
        .clamp(0, 100);
  }

  String get riskLabel {
    if (riskScore <= 20) return 'Low';
    if (riskScore <= 45) return 'Moderate';
    if (riskScore <= 70) return 'Elevated';
    return 'High';
  }

  // Per-metric status helpers
  String get hrStatus {
    if (heartRate <= 60) return 'Low';
    if (heartRate <= 90) return 'Normal';
    if (heartRate <= 110) return 'Elevated';
    return 'High';
  }

  String get brStatus {
    if (breathingRate <= 12) return 'Low';
    if (breathingRate <= 20) return 'Normal';
    if (breathingRate <= 26) return 'Elevated';
    return 'High';
  }

  String get tempStatus {
    if (bodyTemp < 36.1) return 'Low';
    if (bodyTemp <= 37.2) return 'Normal';
    if (bodyTemp <= 37.8) return 'Elevated';
    return 'High';
  }

  String get motionStatus {
    if (motionMagnitude <= 0.5) return 'Still';
    if (motionMagnitude <= 1.5) return 'Normal';
    if (motionMagnitude <= 3.0) return 'Restless';
    return 'Agitated';
  }
}
