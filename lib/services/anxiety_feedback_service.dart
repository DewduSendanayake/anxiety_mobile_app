import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'chest_strap_service.dart';
import 'notification_helper.dart';

class SustainedHighRiskGate {
  final double highThreshold;
  final double recoveryThreshold;
  final Duration requiredDuration;

  DateTime? _highSince;
  bool _alertIssuedForCurrentEpisode = false;

  SustainedHighRiskGate({
    this.highThreshold = 70.0,
    this.recoveryThreshold = 60.0,
    this.requiredDuration = const Duration(minutes: 3),
  });

  bool shouldAlert(double riskScore, DateTime observedAt) {
    if (riskScore <= highThreshold) {
      // Any dip below High breaks continuity. A lower recovery boundary adds
      // hysteresis so one long event cannot create repeated alerts.
      _highSince = null;
      if (riskScore < recoveryThreshold) {
        _alertIssuedForCurrentEpisode = false;
      }
      return false;
    }

    _highSince ??= observedAt;
    if (!_alertIssuedForCurrentEpisode &&
        observedAt.difference(_highSince!) >= requiredDuration) {
      _alertIssuedForCurrentEpisode = true;
      return true;
    }
    return false;
  }

  void reset() {
    _highSince = null;
    _alertIssuedForCurrentEpisode = false;
  }
}

class AnxietyAlertEvent {
  final String eventId;
  final String userId;
  final DateTime detectedAt;
  final double initialRiskScore;
  final double initialHr;
  final double initialBr;
  final double initialMotion;
  final String riskSource;
  bool? confirmedAnxious;
  String? activity;
  String? intervention;
  DateTime? interventionAt;
  bool? interventionCompleted;
  String? alternativeAction;
  DateTime? followupAt;
  double? followupRiskScore;
  double? followupHr;
  double? followupBr;
  double? followupMotion;
  bool? feltBetter;

  AnxietyAlertEvent({
    required this.eventId,
    required this.userId,
    required this.detectedAt,
    required this.initialRiskScore,
    required this.initialHr,
    required this.initialBr,
    required this.initialMotion,
    this.riskSource = 'physiological',
    this.confirmedAnxious,
    this.activity,
    this.intervention,
    this.interventionAt,
    this.interventionCompleted,
    this.alternativeAction,
    this.followupAt,
    this.followupRiskScore,
    this.followupHr,
    this.followupBr,
    this.followupMotion,
    this.feltBetter,
  });

  factory AnxietyAlertEvent.fromJson(Map<String, dynamic> json) {
    return AnxietyAlertEvent(
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String,
      detectedAt: DateTime.parse(json['detected_at'] as String),
      initialRiskScore: (json['initial_risk_score'] as num).toDouble(),
      initialHr: (json['initial_hr'] as num).toDouble(),
      initialBr: (json['initial_br'] as num).toDouble(),
      initialMotion: (json['initial_motion'] as num).toDouble(),
      riskSource: json['risk_source'] as String? ?? 'physiological',
      confirmedAnxious: json['confirmed_anxious'] as bool?,
      activity: json['activity'] as String?,
      intervention: json['intervention'] as String?,
      interventionAt: json['intervention_at'] == null
          ? null
          : DateTime.parse(json['intervention_at'] as String),
      interventionCompleted: json['intervention_completed'] as bool?,
      alternativeAction: json['alternative_action'] as String?,
      followupAt: json['followup_at'] == null
          ? null
          : DateTime.parse(json['followup_at'] as String),
      followupRiskScore: (json['followup_risk_score'] as num?)?.toDouble(),
      followupHr: (json['followup_hr'] as num?)?.toDouble(),
      followupBr: (json['followup_br'] as num?)?.toDouble(),
      followupMotion: (json['followup_motion'] as num?)?.toDouble(),
      feltBetter: json['felt_better'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'event_id': eventId,
    'user_id': userId,
    'detected_at': detectedAt.toUtc().toIso8601String(),
    'initial_risk_score': initialRiskScore,
    'initial_hr': initialHr,
    'initial_br': initialBr,
    'initial_motion': initialMotion,
    'risk_source': riskSource,
    if (confirmedAnxious != null) 'confirmed_anxious': confirmedAnxious,
    if (activity != null) 'activity': activity,
    if (intervention != null) 'intervention': intervention,
    if (interventionAt != null)
      'intervention_at': interventionAt!.toUtc().toIso8601String(),
    if (interventionCompleted != null)
      'intervention_completed': interventionCompleted,
    if (alternativeAction != null) 'alternative_action': alternativeAction,
    if (followupAt != null)
      'followup_at': followupAt!.toUtc().toIso8601String(),
    if (followupRiskScore != null) 'followup_risk_score': followupRiskScore,
    if (followupHr != null) 'followup_hr': followupHr,
    if (followupBr != null) 'followup_br': followupBr,
    if (followupMotion != null) 'followup_motion': followupMotion,
    if (feltBetter != null) 'felt_better': feltBetter,
  };
}

class AnxietyFeedbackService {
  static final AnxietyFeedbackService _instance =
      AnxietyFeedbackService._internal();

  factory AnxietyFeedbackService() => _instance;

  AnxietyFeedbackService._internal();

  static const String _eventsKey = 'anxiety_alert_events_v1';
  String? _userId;
  StreamSubscription<ChestStrapReading>? _readingSubscription;
  DateTime? _lastReadingAt;
  final SustainedHighRiskGate _riskGate = SustainedHighRiskGate();
  double? _latestFusionRisk;
  DateTime? _latestFusionAt;
  final Map<String, Timer> _followupTimers = {};

  Future<void> initializeForUser(String userId) async {
    if (_userId == userId && _readingSubscription != null) return;
    await stop();
    _userId = userId;
    _readingSubscription = ChestStrapService().readingsStream.listen(
      _observeReading,
      onError: (error) => debugPrint('Anxiety alert monitor error: $error'),
    );
    await _restorePendingFollowups();
  }

  Future<void> stop() async {
    await _readingSubscription?.cancel();
    _readingSubscription = null;
    _userId = null;
    _lastReadingAt = null;
    _riskGate.reset();
    _latestFusionRisk = null;
    _latestFusionAt = null;
    for (final timer in _followupTimers.values) {
      timer.cancel();
    }
    _followupTimers.clear();
  }

  void _observeReading(ChestStrapReading reading) {
    final userId = _userId;
    if (userId == null || !reading.isWorn) {
      _resetHighEpisode();
      return;
    }

    final now = DateTime.now();
    if (_lastReadingAt != null &&
        now.difference(_lastReadingAt!) > const Duration(seconds: 10)) {
      _resetHighEpisode();
    }
    _lastReadingAt = now;

    final hasFreshFusion =
        _latestFusionRisk != null &&
        _latestFusionAt != null &&
        now.difference(_latestFusionAt!) < const Duration(seconds: 90);
    final monitoredRisk = hasFreshFusion
        ? _latestFusionRisk!
        : reading.riskScore;

    if (_riskGate.shouldAlert(monitoredRisk, now)) {
      unawaited(
        _createAlert(
          userId,
          reading,
          now,
          monitoredRisk,
          hasFreshFusion ? 'fusion' : 'physiological',
        ),
      );
    }
  }

  void updateFusionRisk(double riskScore) {
    _latestFusionRisk = riskScore.clamp(0.0, 100.0);
    _latestFusionAt = DateTime.now();
  }

  void _resetHighEpisode() {
    _riskGate.reset();
  }

  Future<void> _createAlert(
    String userId,
    ChestStrapReading reading,
    DateTime detectedAt,
    double monitoredRisk,
    String riskSource,
  ) async {
    final event = AnxietyAlertEvent(
      eventId: 'anx:${detectedAt.toUtc().millisecondsSinceEpoch}',
      userId: userId,
      detectedAt: detectedAt,
      initialRiskScore: monitoredRisk,
      initialHr: reading.meanHR,
      initialBr: reading.meanBR,
      initialMotion: reading.stdAccMag,
      riskSource: riskSource,
    );
    await _upsertEvent(event);
    await _upload(event);
    await NotificationHelper.showAnxietyAlert(eventId: event.eventId);
  }

  static Future<List<AnxietyAlertEvent>> _loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_eventsKey);
    if (encoded == null || encoded.isEmpty) return [];
    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      return decoded
          .map(
            (item) => AnxietyAlertEvent.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (error) {
      debugPrint('Could not read saved anxiety events: $error');
      return [];
    }
  }

  static Future<void> _saveEvents(List<AnxietyAlertEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    events.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    final retained = events.take(100).map((event) => event.toJson()).toList();
    await prefs.setString(_eventsKey, jsonEncode(retained));
  }

  static Future<void> _upsertEvent(AnxietyAlertEvent event) async {
    final events = await _loadEvents();
    final index = events.indexWhere((saved) => saved.eventId == event.eventId);
    if (index == -1) {
      events.add(event);
    } else {
      events[index] = event;
    }
    await _saveEvents(events);
  }

  static Future<AnxietyAlertEvent?> getEvent(String eventId) async {
    final events = await _loadEvents();
    for (final event in events) {
      if (event.eventId == eventId) return event;
    }
    return null;
  }

  static Future<void> _upload(AnxietyAlertEvent event) async {
    await ApiService.sendAnxietyFeedback(event.toJson());
  }

  static Future<void> recordConfirmation(String eventId, bool confirmed) async {
    final event = await getEvent(eventId);
    if (event == null) return;
    event.confirmedAnxious = confirmed;
    await _upsertEvent(event);
    await _upload(event);
  }

  static Future<void> recordContext(String eventId, String activity) async {
    final event = await getEvent(eventId);
    if (event == null) return;
    event.activity = activity;
    await _upsertEvent(event);
    await _upload(event);
  }

  Future<void> recordIntervention({
    required String eventId,
    required bool completedGuidance,
    String? alternativeAction,
  }) async {
    final event = await getEvent(eventId);
    if (event == null) return;
    event.intervention = completedGuidance ? '2-minute paced breathing' : null;
    event.interventionAt = DateTime.now();
    event.interventionCompleted = completedGuidance;
    event.alternativeAction = (alternativeAction?.trim().isEmpty ?? true)
        ? null
        : alternativeAction!.trim();
    await _upsertEvent(event);
    await _upload(event);
    _scheduleFollowup(eventId, const Duration(minutes: 5));
  }

  Future<void> _restorePendingFollowups() async {
    final events = await _loadEvents();
    final now = DateTime.now();
    for (final event in events) {
      if (event.userId != _userId ||
          event.interventionAt == null ||
          event.followupAt != null) {
        continue;
      }
      final dueAt = event.interventionAt!.add(const Duration(minutes: 5));
      final remaining = dueAt.difference(now);
      _scheduleFollowup(
        event.eventId,
        remaining.isNegative ? Duration.zero : remaining,
      );
    }
  }

  void _scheduleFollowup(String eventId, Duration delay) {
    _followupTimers[eventId]?.cancel();
    _followupTimers[eventId] = Timer(delay, () => _captureFollowup(eventId));
  }

  Future<void> _captureFollowup(String eventId) async {
    _followupTimers.remove(eventId);
    final event = await getEvent(eventId);
    if (event == null) return;
    final reading = ChestStrapService().hasLiveWornReading
        ? ChestStrapService().lastReading
        : null;
    event.followupAt = DateTime.now();
    if (reading != null && reading.isWorn) {
      event.followupRiskScore = reading.riskScore;
      event.followupHr = reading.meanHR;
      event.followupBr = reading.meanBR;
      event.followupMotion = reading.stdAccMag;
    }
    await _upsertEvent(event);
    await _upload(event);
    await NotificationHelper.showAnxietyFollowup(
      eventId: eventId,
      signalsImproved:
          event.followupRiskScore != null &&
          event.followupRiskScore! <= event.initialRiskScore - 10.0,
    );
  }

  static Future<void> recordFeltBetter(String eventId, bool feltBetter) async {
    final event = await getEvent(eventId);
    if (event == null) return;
    event.feltBetter = feltBetter;
    await _upsertEvent(event);
    await _upload(event);
  }

  static Future<void> handleNotificationAction({
    required String? actionId,
    required String? payload,
  }) async {
    if (payload == null || !payload.startsWith('anxiety_checkin:')) return;
    final eventId = payload.substring('anxiety_checkin:'.length);
    if (actionId == NotificationHelper.anxietyYesAction) {
      await recordConfirmation(eventId, true);
    } else if (actionId == NotificationHelper.anxietyNoAction) {
      await recordConfirmation(eventId, false);
    }
  }
}
