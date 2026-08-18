import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Main-isolate Supabase integration for research data.
///
/// Credentials are supplied at build/run time:
/// --dart-define=SUPABASE_URL=...
/// --dart-define=SUPABASE_PUBLISHABLE_KEY=...
///
/// Never place a service-role/secret key in the mobile app.
class SupabaseResearchService {
  SupabaseResearchService._();

  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool _initialized = false;

  static bool get isConfigured =>
      _url.trim().isNotEmpty && _publishableKey.trim().isNotEmpty;

  static bool get isInitialized => _initialized;

  static Future<bool> initialize() async {
    if (_initialized) return true;
    if (!isConfigured) {
      debugPrint(
        'Supabase: not configured. Provide SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY with --dart-define.',
      );
      return false;
    }

    try {
      await Supabase.initialize(
        url: _url,
        publishableKey: _publishableKey,
      );
      _initialized = true;
      debugPrint('Supabase: initialized.');
      return true;
    } catch (e, st) {
      debugPrint('Supabase initialization failed: $e');
      debugPrint('$st');
      return false;
    }
  }

  static SupabaseClient? get client {
    if (!_initialized) return null;
    return Supabase.instance.client;
  }

  /// Ensures this installation has an authenticated Supabase identity and a
  /// row mapping that identity to the pseudonymous research participant code.
  static Future<String?> ensureParticipant(String participantCode) async {
    if (participantCode.isEmpty || participantCode == 'No_User_ID') return null;
    if (!await initialize()) return null;

    final supabase = client!;
    try {
      if (supabase.auth.currentSession == null) {
        await supabase.auth.signInAnonymously(
          data: {'participant_code': participantCode},
        );
      }

      final authUser = supabase.auth.currentUser;
      if (authUser == null) {
        debugPrint('Supabase: anonymous authentication returned no user.');
        return null;
      }

      await supabase.from('participants').upsert(
        {
          'auth_user_id': authUser.id,
          'participant_code': participantCode,
          'active': true,
        },
        onConflict: 'auth_user_id',
      );

      return authUser.id;
    } catch (e, st) {
      debugPrint('Supabase participant registration failed: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// Inserts a batch of already-normalized research events. RLS verifies that
  /// every row belongs to the currently authenticated Supabase user.
  static Future<void> insertSensorEvents(
    String participantCode,
    List<Map<String, dynamic>> queuedEvents,
  ) async {
    if (queuedEvents.isEmpty) return;

    final authUserId = await ensureParticipant(participantCode);
    if (authUserId == null) {
      throw StateError('Supabase participant is not available.');
    }

    final rows = queuedEvents.map((event) {
      final rawValue = event['value'];
      dynamic valueJson = rawValue;
      if (rawValue is String) {
        try {
          valueJson = _decodeJsonObject(rawValue);
        } catch (_) {
          valueJson = {'value': rawValue};
        }
      }
      if (valueJson is! Map && valueJson is! List) {
        valueJson = {'value': valueJson};
      }

      return <String, dynamic>{
        'event_id': event['eventId'],
        'auth_user_id': authUserId,
        'participant_code': participantCode,
        'event_time': event['timestamp'],
        'event_type': event['dataType'],
        'value_json': valueJson,
        'source': event['source'] ?? 'android',
      };
    }).toList();

    // event_id is generated once when an event enters the local queue. Upsert
    // makes network retries idempotent instead of creating duplicate rows.
    await client!.from('sensor_events').upsert(
      rows,
      onConflict: 'event_id',
      ignoreDuplicates: true,
    );
  }

  static dynamic _decodeJsonObject(String value) {
    // jsonDecode kept behind a helper to keep event normalization in one place.
    // ignore: avoid_dynamic_calls
    return const _JsonDecoder().decode(value);
  }
}

/// Tiny wrapper lets this file avoid exporting dart:convert implementation
/// details throughout the service API.
class _JsonDecoder {
  const _JsonDecoder();

  dynamic decode(String source) {
    return jsonDecode(source);
  }
}
