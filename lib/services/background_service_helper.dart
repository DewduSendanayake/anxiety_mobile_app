import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'background/service_config.dart';

class BackgroundServiceHelper {
  // A local memory buffer to hold data before sending
  static final List<Map<String, dynamic>> _buffer = [];
  static bool _isSyncing = false;

  // CONFIGURATION: How many seconds to wait before sending the batch
  // Reduced to 4s for faster delivery during debugging; can be tuned.
  static const int _batchIntervalSeconds = 4;
  static Timer? _timer;

  /// Call this instead of sending immediately.
  /// It adds to a list and starts the timer if not running.
  static Future<void> sendToSheet(
    String userId,
    String type,
    String value,
  ) async {
    final dataMap = {
      "userId": userId,
      "dataType": type,
      "value": value,
      "timestamp": DateTime.now().toIso8601String(),
    };

    _buffer.add(dataMap);
    debugPrint(
      "[BackgroundServiceHelper] Buffered data user=$userId type=$type time=${DateTime.now().toIso8601String()} bufferSize=${_buffer.length}",
    );

    // If timer isn't running, start it.
    _timer ??= Timer(
      const Duration(seconds: _batchIntervalSeconds),
      _flushBuffer,
    );
  }

  /// Sends everything in the buffer as ONE request
  static Future<void> _flushBuffer() async {
    _timer?.cancel();
    _timer = null;

    if (_buffer.isEmpty || _isSyncing) return;
    _isSyncing = true;

    // Create a copy of the buffer to send
    List<Map<String, dynamic>> batchToSend = List.from(_buffer);
    _buffer.clear(); // Clear immediate buffer so new data can come in

    debugPrint(
      "[BackgroundServiceHelper] Flushing batch of ${batchToSend.length} items at ${DateTime.now().toIso8601String()}",
    );

    try {
      // Send the WHOLE LIST as JSON
      var response = await http
          .post(
            Uri.parse(ServiceConfig.googleScriptUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(batchToSend),
          )
          .timeout(const Duration(seconds: 20));

      debugPrint(
        "[BackgroundServiceHelper] POST response: ${response.statusCode} body=${response.body}",
      );
      if (response.statusCode == 200 || response.statusCode == 302) {
        // Success!
        debugPrint(
          "[BackgroundServiceHelper] Successfully batched ${batchToSend.length} items.",
        );
      } else {
        throw Exception(
          "Server Error ${response.statusCode} - ${response.body}",
        );
      }
    } catch (e) {
      debugPrint("[BackgroundServiceHelper] Batch failed, saving offline: $e");
      // If failed, put items back into offline queue
      await _saveToOfflineQueue(batchToSend);
      // Schedule a short retry to attempt to clear transient failures
      try {
        Timer(const Duration(seconds: 30), () {
          retryOfflineQueue();
        });
        debugPrint("[BackgroundServiceHelper] Scheduled retry in 30s");
      } catch (_) {}
    } finally {
      _isSyncing = false;
    }
  }

  static Future<void> _saveToOfflineQueue(
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList('offline_queue') ?? [];

    for (var item in items) {
      queue.add(jsonEncode(item));
    }
    await prefs.setStringList('offline_queue', queue);
    debugPrint(
      "[BackgroundServiceHelper] Saved ${items.length} items to offline_queue (total=${queue.length})",
    );
  }

  // Call this occasionally (e.g. on app start) to retry failed items
  static Future<void> retryOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList('offline_queue') ?? [];
    debugPrint(
      "[BackgroundServiceHelper] retryOfflineQueue called, found=${queue.length} items",
    );
    if (queue.isEmpty) return;

    // Convert strings back to maps
    List<Map<String, dynamic>> batch = [];
    for (var str in queue) {
      batch.add(jsonDecode(str));
    }

    // Clear queue assuming we will try to send now
    await prefs.setStringList('offline_queue', []);

    // Add to main buffer
    _buffer.addAll(batch);

    // Trigger flush
    await _flushBuffer();
  }

  static Future<String> getCachedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? "Unknown";
  }
}
