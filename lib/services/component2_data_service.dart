import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Fetches the validated Component 2 behavioural outputs and stores only
/// display-safe, descriptive data for the Flutter UI.
///
/// Configure the backend at build/run time with:
///   --dart-define=COMPONENT2_API_URL=https://your-component2-api.example
///
/// Expected endpoint:
///   GET /behavioral/{participantId}
///
/// The response may either be the observation payload itself, or an envelope
/// containing `observation_payload`, `passive_metrics`, `day_coverage` and
/// `checkin_history`.
///
/// IMPORTANT: GATv2/risk probabilities are deliberately not persisted into the
/// participant-facing cache. The current research evidence does not support a
/// behavioural anxiety-risk score for display or active fusion.
class Component2DataService {
  static const String _baseUrl = String.fromEnvironment(
    'COMPONENT2_API_URL',
    defaultValue: '',
  );

  static const Duration _timeout = Duration(seconds: 15);

  static bool get isConfigured => _baseUrl.trim().isNotEmpty;

  static Future<Component2SyncResult> sync(String participantId) async {
    final id = participantId.trim();
    if (id.isEmpty) {
      return const Component2SyncResult(
        success: false,
        status: 'missing_participant_id',
      );
    }

    if (!isConfigured) {
      debugPrint(
        '[Component2] COMPONENT2_API_URL is not configured; using cached/local data.',
      );
      return const Component2SyncResult(
        success: false,
        status: 'not_configured',
      );
    }

    try {
      final base = _baseUrl.endsWith('/')
          ? _baseUrl.substring(0, _baseUrl.length - 1)
          : _baseUrl;
      final uri = Uri.parse('$base/behavioral/${Uri.encodeComponent(id)}');
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
          '[Component2] Sync failed: HTTP ${response.statusCode} ${response.body}',
        );
        return Component2SyncResult(
          success: false,
          status: 'http_${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const Component2SyncResult(
          success: false,
          status: 'invalid_payload',
        );
      }

      final prefs = await SharedPreferences.getInstance();

      final rawObservation = decoded['observation_payload'];
      final observation = rawObservation is Map<String, dynamic>
          ? rawObservation
          : decoded;

      final safeObservation = _displaySafeObservationPayload(observation, id);
      if (_looksLikeObservationPayload(safeObservation)) {
        await prefs.setString(
          'c2_observation_payload',
          jsonEncode(safeObservation),
        );
      }

      final passive = decoded['passive_metrics'];
      if (passive is Map<String, dynamic>) {
        await prefs.setString('c2_passive_metrics', jsonEncode(passive));
      }

      final coverage = decoded['day_coverage'];
      if (coverage is List) {
        await prefs.setString('c2_day_coverage', jsonEncode(coverage));
      }

      final checkIns = decoded['checkin_history'];
      if (checkIns is List) {
        await prefs.setString('c2_checkin_history', jsonEncode(checkIns));
      }

      // Keep the deployment contract explicit: absence of a behavioural score
      // means "withheld/not validated", not "low risk".
      await prefs.setString(
        'c2_fusion_handoff',
        jsonEncode(buildFusionHandoff(participantId: id)),
      );

      await prefs.setString(
        'c2_last_sync_utc',
        DateTime.now().toUtc().toIso8601String(),
      );

      return const Component2SyncResult(success: true, status: 'ok');
    } catch (e, st) {
      debugPrint('[Component2] Sync error: $e');
      debugPrint('$st');
      return const Component2SyncResult(
        success: false,
        status: 'network_or_parse_error',
      );
    }
  }

  /// Contract for the multimodal fusion team while Component 2 remains
  /// insufficiently validated for inferential use.
  ///
  /// `behavioral_score` is intentionally null. A numeric 0 would incorrectly
  /// communicate "very low anxiety" rather than "no validated estimate".
  static Map<String, dynamic> buildFusionHandoff({
    required String participantId,
  }) {
    return {
      'component': 'behavioral',
      'participant_id': participantId,
      'model_status': 'withheld_pending_validation',
      'fusion_eligible': false,
      'behavioral_score': null,
      'recommended_weight': 0.0,
      'display_permitted': false,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static bool _looksLikeObservationPayload(Map<String, dynamic> payload) {
    return payload.containsKey('observations') ||
        payload.containsKey('baseline_ready') ||
        payload.containsKey('reportable');
  }

  /// Allow-list only fields the participant-facing page may consume.
  /// Research-only model probabilities, risk bands, phenotype labels and
  /// attention explanations are intentionally excluded.
  static Map<String, dynamic> _displaySafeObservationPayload(
    Map<String, dynamic> source,
    String participantId,
  ) {
    return {
      'participant_id': source['participant_id'] ?? participantId,
      if (source['window'] is Map) 'window': source['window'],
      'baseline_ready': source['baseline_ready'] ?? false,
      'reportable': source['reportable'] ?? false,
      if (source['observations'] is Map) 'observations': source['observations'],
      if (source['change_detection'] is Map)
        'change_detection': source['change_detection'],
      if (source['data_quality'] is Map) 'data_quality': source['data_quality'],
      if (source['blocking_issues'] is List)
        'blocking_issues': source['blocking_issues'],
    };
  }
}

class Component2SyncResult {
  final bool success;
  final String status;

  const Component2SyncResult({required this.success, required this.status});
}
