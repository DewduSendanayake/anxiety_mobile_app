import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'background_service.dart'; // To access the kGoogleScriptUrl constant

class BackgroundServiceHelper {
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

    try {
      // Direct send
      var response = await http
          .post(
            Uri.parse(kGoogleScriptUrl),
            headers: {
              "Content-Type": "text/plain",
            }, // 'text/plain' prevents CORS preflight issues
            body: jsonEncode(dataMap),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 && response.statusCode != 302) {
        throw Exception("Server Error");
      }
    } catch (e) {
      // If failed, save to offline queue
      await _saveToQueue(dataMap);
    }
  }

  static Future<void> _saveToQueue(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList('offline_queue') ?? [];
    queue.add(jsonEncode(data));
    await prefs.setStringList('offline_queue', queue);
  }

  static Future<String> getCachedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? "Unknown";
  }
}
