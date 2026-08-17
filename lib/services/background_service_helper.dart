import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'background/service_config.dart';

class BackgroundServiceHelper {
  static bool _isSyncing = false;
  static const int _batchIntervalSeconds = 10;
  static Timer? _timer;

  /// true  → main UI isolate  → writes to 'offline_queue_main'
  /// false → background isolate → writes to 'offline_queue_bg'
  static bool isMainIsolate = true;

  static String get _queueKey =>
      isMainIsolate ? 'offline_queue_main' : 'offline_queue_bg';

  /// Storage-neutral research event entry point.
  ///
  /// Today the queue is flushed to the existing Google Apps Script endpoint.
  /// Later the uploader can be switched to Supabase/another API without
  /// changing sensor collectors or event producers.
  static Future<void> enqueueResearchEvent(
    String userId,
    String type,
    dynamic value, {
    bool immediate = false,
    DateTime? eventTime,
  }) async {
    final dataMap = <String, dynamic>{
      'userId': userId,
      'dataType': type,
      'value': value is String ? value : jsonEncode(value),
      'timestamp': (eventTime ?? DateTime.now()).toIso8601String(),
      'token': ServiceConfig.authToken,
    };

    await _saveToOfflineQueue([dataMap]);

    if (immediate) {
      _timer?.cancel();
      _timer = null;
      await retryOfflineQueue();
    } else {
      _timer ??= Timer(
        const Duration(seconds: _batchIntervalSeconds),
        retryOfflineQueue,
      );
    }
  }

  /// Backwards-compatible alias while the rest of the app migrates away from
  /// storage-specific naming.
  static Future<void> sendToSheet(
    String userId,
    String type,
    String value, {
    bool immediate = false,
  }) =>
      enqueueResearchEvent(
        userId,
        type,
        value,
        immediate: immediate,
      );

  static Future<void> _saveToOfflineQueue(
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    List<String> queue = prefs.getStringList(_queueKey) ?? [];

    for (final item in items) {
      if (queue.length >= 10000) {
        debugPrint('⚠️ Offline queue full — oldest item dropped.');
        queue.removeAt(0);
      }
      queue.add(jsonEncode(item));
    }

    await prefs.setStringList(_queueKey, queue);
  }

  /// Uploads every queued item from this isolate's queue.
  ///
  /// The current transport is the legacy Google Apps Script endpoint. Keeping
  /// transport here means collectors remain unchanged when the destination is
  /// later switched to Supabase.
  static Future<void> retryOfflineQueue() async {
    _timer?.cancel();
    _timer = null;

    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      List<String> queue = prefs.getStringList(_queueKey) ?? [];

      final oldQueue = prefs.getStringList('offline_queue') ?? <String>[];
      if (oldQueue.isNotEmpty) {
        queue.insertAll(0, oldQueue);
        await prefs.remove('offline_queue');
        debugPrint('📦 Migrated ${oldQueue.length} items from legacy queue.');
      }

      if (queue.isEmpty) return;

      debugPrint('🔄 Syncing queue [$_queueKey]: ${queue.length} items');

      const chunkSize = 50;
      int failedFrom = -1;

      for (int i = 0; i < queue.length; i += chunkSize) {
        final end = i + chunkSize < queue.length ? i + chunkSize : queue.length;
        final chunkStrings = queue.sublist(i, end);
        final batch = chunkStrings
            .map((s) => jsonDecode(s) as Map<String, dynamic>)
            .toList();

        try {
          final response = await http
              .post(
                Uri.parse(ServiceConfig.googleScriptUrl),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode(batch),
              )
              .timeout(const Duration(seconds: 30));

          final ok = response.statusCode == 200 ||
              response.statusCode == 302 ||
              _isSuccessBody(response.body);

          if (ok) {
            debugPrint('✅ Chunk [$i–${end - 1}] sent (${batch.length} items)');
          } else {
            debugPrint(
              '⚠️ Server error on chunk [$i–${end - 1}]: ${response.statusCode}',
            );
            failedFrom = i;
            break;
          }
        } catch (e) {
          debugPrint('❌ Chunk [$i–${end - 1}] failed: $e');
          failedFrom = i;
          break;
        }
      }

      await prefs.reload();
      final freshQueue = prefs.getStringList(_queueKey) ?? <String>[];
      final remaining = <String>[];

      if (failedFrom >= 0) {
        remaining.addAll(queue.sublist(failedFrom));
      }
      if (freshQueue.length > queue.length) {
        remaining.addAll(freshQueue.sublist(queue.length));
      }

      await prefs.setStringList(_queueKey, remaining);

      if (remaining.isEmpty) {
        debugPrint('✅ Queue [$_queueKey] fully cleared.');
      } else {
        debugPrint('⚠️ ${remaining.length} items still pending in [$_queueKey].');
      }
    } finally {
      _isSyncing = false;
    }
  }

  static bool _isSuccessBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded['status'] == 'success' || decoded['status'] == 'partial';
    } catch (_) {
      return body.contains('success');
    }
  }

  static Future<String> getCachedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? 'No_User_ID';
  }

  static Future<bool> isServiceRunning() async {
    if (kIsWeb) return false;
    try {
      return await FlutterBackgroundService().isRunning();
    } catch (e) {
      debugPrint('Background service status unavailable: $e');
      return false;
    }
  }

  static Future<int> getOfflineQueueSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final mainQ = prefs.getStringList('offline_queue_main') ?? <String>[];
    final bgQ = prefs.getStringList('offline_queue_bg') ?? <String>[];
    final legacyQ = prefs.getStringList('offline_queue') ?? <String>[];
    return mainQ.length + bgQ.length + legacyQ.length;
  }
}
