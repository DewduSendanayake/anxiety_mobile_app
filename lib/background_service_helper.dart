import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'background_service.dart';

class BackgroundServiceHelper {
  static final List<Map<String, dynamic>> _buffer = [];
  static bool _isSyncing = false;
  static const int _batchIntervalSeconds = 10;
  static Timer? _timer;

  // ── Must match the AUTH_TOKEN set in Apps Script setupScript() ──
  static const String _authToken = "7c09db655b5f697a4faf0b18a517d5fb";

  /// Add data to the buffer. Starts the flush timer if not already running.
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
      "token": _authToken,
    };

    _buffer.add(dataMap);

    _timer ??= Timer(
      const Duration(seconds: _batchIntervalSeconds),
      _flushBuffer,
    );
  }

  /// Flush the buffer — send everything as one POST request.
  static Future<void> _flushBuffer() async {
    _timer?.cancel();
    _timer = null;

    if (_buffer.isEmpty || _isSyncing) return;
    _isSyncing = true;

    final List<Map<String, dynamic>> batchToSend = List.from(_buffer);
    _buffer.clear();

    try {
      final response = await http
          .post(
            Uri.parse(kGoogleScriptUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(batchToSend),
          )
          .timeout(const Duration(seconds: 25));

      // Google Apps Script returns 302 redirect on success — follow it
      if (response.statusCode == 200 ||
          response.statusCode == 302 ||
          _isSuccessBody(response.body)) {
        print("✅ Batch sent: ${batchToSend.length} items");
      } else {
        throw Exception(
          "Server Error ${response.statusCode}: ${response.body}",
        );
      }
    } catch (e) {
      print("❌ Batch failed, saving to offline queue: $e");
      await _saveToOfflineQueue(batchToSend);
    } finally {
      _isSyncing = false;
    }
  }

  /// Check if the response body indicates success (handles redirect responses).
  static bool _isSuccessBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded['status'] == 'success' || decoded['status'] == 'partial';
    } catch (_) {
      return false;
    }
  }

  /// Save failed items to SharedPreferences for later retry.
  static Future<void> _saveToOfflineQueue(
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList('offline_queue') ?? [];

    // Cap offline queue at 5000 items to prevent unbounded storage growth
    // (5000 items × ~200 bytes = ~1MB max)
    for (var item in items) {
      if (queue.length >= 5000) {
        print("⚠️ Offline queue full (5000 items). Oldest item dropped.");
        queue.removeAt(0);
      }
      queue.add(jsonEncode(item));
    }
    await prefs.setStringList('offline_queue', queue);
    print("📦 Offline queue size: ${queue.length}");
  }

  /// Retry all queued offline items. Call on app start and when connectivity restored.
  static Future<void> retryOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList('offline_queue') ?? [];
    if (queue.isEmpty) return;

    print("🔄 Retrying offline queue: ${queue.length} items");

    // Send in chunks of 50 to avoid oversized requests
    const chunkSize = 50;
    List<String> remaining = [];

    for (int i = 0; i < queue.length; i += chunkSize) {
      final chunk = queue.skip(i).take(chunkSize).toList();
      final batch = chunk
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList();

      try {
        final response = await http
            .post(
              Uri.parse(kGoogleScriptUrl),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(batch),
            )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode == 200 ||
            response.statusCode == 302 ||
            _isSuccessBody(response.body)) {
          print("✅ Offline chunk sent: ${batch.length} items");
        } else {
          remaining.addAll(chunk);
        }
      } catch (e) {
        print("❌ Offline retry chunk failed: $e");
        remaining.addAll(chunk);
        break; // Stop retrying if network is still down
      }
    }

    // Save only the items that still failed
    await prefs.setStringList('offline_queue', remaining);

    if (remaining.isEmpty) {
      print("✅ Offline queue fully cleared");
    } else {
      print("⚠️ ${remaining.length} items still pending");
    }
  }

  static Future<String> getCachedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? "Unknown";
  }

  /// Get current offline queue size (for debug display).
  static Future<int> getOfflineQueueSize() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('offline_queue') ?? []).length;
  }
}
