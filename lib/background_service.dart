import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:call_log/call_log.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:telephony/telephony.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// --- CONFIGURATION ---
// Ensure this URL is correct before building the APK
const String GOOGLE_SCRIPT_URL =
    "https://script.google.com/macros/s/AKfycbwerN52adyNYBf0uQ7BQuCb43VnDKX5Qft2afDoObFO6CKxc0OWqJM4UMR7e0aumMhgwQ/exec";

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'research_channel',
    'Research Monitoring Service', // Improved Name
    description: 'Ensures data collection continues in the background',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'research_channel',
      initialNotificationTitle: 'Research Active',
      initialNotificationContent: 'Monitoring safely in background...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Get User ID immediately
  final prefs = await SharedPreferences.getInstance();
  String userId = prefs.getString('user_id') ?? "Unknown";

  // Run data collection every 15 minutes
  Timer.periodic(const Duration(minutes: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "Research Active",
          content:
              "Last Sync: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
        );
      }
    }

    // 1. Try to sync any OLD data that failed to send previously
    await BackgroundServiceHelper.syncOfflineQueue();

    // 2. Collect NEW Data
    try {
      // Location
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await BackgroundServiceHelper.sendToSheet(
        userId,
        "Location",
        "${position.latitude},${position.longitude}",
      );

      // Calls (Last 24h)
      int now = DateTime.now().millisecondsSinceEpoch;
      Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: now - (86400000),
      );
      await BackgroundServiceHelper.sendToSheet(
        userId,
        "Calls_24h",
        entries.length.toString(),
      );

      // SMS (Today)
      Telephony telephony = Telephony.instance;
      List<SmsMessage> messages = await telephony.getInboxSms();
      int smsCount = messages
          .where(
            (m) =>
                DateTime.fromMillisecondsSinceEpoch(m.date ?? 0).day ==
                DateTime.now().day,
          )
          .length;
      await BackgroundServiceHelper.sendToSheet(
        userId,
        "SMS_Today",
        smsCount.toString(),
      );

      // App Usage (Top App in last 15 mins)
      DateTime end = DateTime.now();
      DateTime start = end.subtract(const Duration(minutes: 15));
      List<UsageInfo> usage = await UsageStats.queryUsageStats(start, end);

      // Sort by time in foreground
      usage.sort(
        (a, b) =>
            (int.parse(b.totalTimeInForeground!) -
            int.parse(a.totalTimeInForeground!)),
      );

      if (usage.isNotEmpty) {
        await BackgroundServiceHelper.sendToSheet(
          userId,
          "Top_App",
          usage.first.packageName ?? "Unknown",
        );
      }
    } catch (e) {
      print("Collection Error: $e");
    }
  });
}

// --- HELPER CLASS FOR ROBUST DATA SENDING ---
class BackgroundServiceHelper {
  // 1. Send Data (With Offline Fallback)
  static Future<void> sendToSheet(
    String userId,
    String type,
    String value,
  ) async {
    final dataMap = {
      "userId": userId,
      "dataType": type,
      "value": value,
      "timestamp": DateTime.now().toString(),
    };

    try {
      // Try sending immediately
      var response = await http
          .post(
            Uri.parse(GOOGLE_SCRIPT_URL),
            headers: {"Content-Type": "text/plain"},
            body: jsonEncode(dataMap),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 && response.statusCode != 302) {
        throw Exception("Server Error: ${response.statusCode}");
      }
      print("✅ Data Sent: $type");
    } catch (e) {
      print("⚠️ Upload Failed ($type). Saving to offline queue.");
      await _saveToQueue(dataMap);
    }
  }

  // 2. Save failed data to SharedPreferences
  static Future<void> _saveToQueue(Map<String, String> data) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList('offline_queue') ?? [];
    queue.add(jsonEncode(data));
    await prefs.setStringList('offline_queue', queue);
  }

  // 3. Sync Offline Queue (Retries sending stored data)
  static Future<void> syncOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList('offline_queue') ?? [];

    if (queue.isEmpty) return;

    print("🔄 Attempting to sync ${queue.length} offline records...");
    List<String> remainingQueue = [];
    bool internetRestored = false;

    for (String jsonStr in queue) {
      try {
        Map<String, dynamic> data = jsonDecode(jsonStr);

        var response = await http
            .post(
              Uri.parse(GOOGLE_SCRIPT_URL),
              headers: {"Content-Type": "text/plain"},
              body: jsonEncode(data),
            )
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 || response.statusCode == 302) {
          internetRestored = true;
        } else {
          remainingQueue.add(jsonStr); // Keep if server error
        }
      } catch (e) {
        remainingQueue.add(jsonStr); // Keep if connection error
      }
    }

    if (internetRestored) {
      print("✅ Offline Sync Complete. Remaining: ${remainingQueue.length}");
    }

    await prefs.setStringList('offline_queue', remainingQueue);
  }

  // 4. NEW: Helper to get Cached ID for UI
  static Future<String> getCachedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? "Unknown";
  }
}
