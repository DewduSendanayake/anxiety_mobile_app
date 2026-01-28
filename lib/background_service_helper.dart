import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'background_service.dart';

class BackgroundServiceHelper {
  // A local memory buffer to hold data before sending
  static final List<Map<String, dynamic>> _buffer = [];
  static bool _isSyncing = false;

  // CONFIGURATION: How many seconds to wait before sending the batch
  static const int _batchIntervalSeconds = 6;
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

    try {
      // Send the WHOLE LIST as JSON
      var response = await http
          .post(
            Uri.parse(kGoogleScriptUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(batchToSend),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 || response.statusCode == 302) {
        // Success!
        print("Successfully batched ${batchToSend.length} items.");
      } else {
        throw Exception("Server Error ${response.statusCode}");
      }
    } catch (e) {
      print("Batch failed, saving offline: $e");
      // If failed, put items back into offline queue
      await _saveToOfflineQueue(batchToSend);
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
  }

  // Call this occasionally (e.g. on app start) to retry failed items
  static Future<void> retryOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList('offline_queue') ?? [];
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
    _flushBuffer();
  }

  static Future<String> getCachedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? "Unknown";
  }
}
