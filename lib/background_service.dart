// Backwards-compatible re-export for moved background service implementation.
export 'services/background/background_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:call_log/call_log.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart'; // UPDATED PACKAGE
// HTTP not used here; keep network calls in helper
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:screen_state/screen_state.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'background_service_helper.dart';

// GOOGLE SCRIPT URL
const String kGoogleScriptUrl =
    "https://script.google.com/macros/s/AKfycbyHA5394Trxj3DYwTsop2xwJeS07mmA3JUea_xc3ZxWcYhx_WZPpN9EwdSF936kl4ll/exec";

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'research_channel_01',
    'Data Collection Service',
    description: 'Running background research tasks',
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
      notificationChannelId: 'research_channel_01',
      initialNotificationTitle: 'Research Active',
      initialNotificationContent: 'Collecting anonymous usage data...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  String userId = prefs.getString('user_id') ?? "Unknown_User";

  // Attempt to resend any offline-queued items when background service starts
  try {
    await BackgroundServiceHelper.retryOfflineQueue();
  } catch (e) {
    debugPrint('Retry offline queue on service start failed: $e');
  }

  // Setup connectivity listener in background service to retry when online
  try {
    Connectivity().onConnectivityChanged.listen((result) async {
      if (result != ConnectivityResult.none) {
        try {
          await BackgroundServiceHelper.retryOfflineQueue();
        } catch (e) {
          debugPrint('Background service connectivity retry failed: $e');
        }
      }
    });
  } catch (e) {
    debugPrint('Background connectivity listener setup failed: $e');
  }

  // 1. SETUP NOTIFICATIONS
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 2. REAL-TIME: SCREEN STATE
  // FIX: Removed underscore to fix lint warning
  Screen screen = Screen();
  try {
    screen.screenStateStream?.listen((ScreenStateEvent event) {
      String status = "Unknown";
      if (event == ScreenStateEvent.SCREEN_ON) status = "Screen_On";
      if (event == ScreenStateEvent.SCREEN_OFF) status = "Screen_Off";
      if (event == ScreenStateEvent.SCREEN_UNLOCKED) status = "Screen_Unlocked";

      _sendData(userId, "Screen_Event", status);
    });
  } catch (e) {
    debugPrint("Screen State Error: $e");
  }

  // 3. REAL-TIME: ACCELEROMETER (Stress Proxy)
  try {
    // FIX: Updated to new Stream API
    accelerometerEventStream().listen((AccelerometerEvent event) {
      // Calculate magnitude
      double magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      // Filter for significant movements to save bandwidth
      if (magnitude > 15.0) {
        _sendData(userId, "High_Motion_Event", magnitude.toStringAsFixed(2));
      }
    });
  } catch (e) {
    debugPrint("Sensor Error: $e");
  }

  // 4. PERIODIC: HEAVY TASKS (Every 15 Minutes)
  Timer.periodic(const Duration(minutes: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        flutterLocalNotificationsPlugin.show(
          888,
          'Research Active',
          'Last Sync: ${DateTime.now().hour}:${DateTime.now().minute}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'research_channel_01',
              'Data Collection Service',
              icon: 'ic_bg_service_small',
              ongoing: true,
            ),
          ),
        );
      }
    }

    await _collectAndSync(userId);
  });

  // 5. DAILY: Rating Notification Checker (Every minute)
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    try {
      await _maybeShowRatingNotification(
        userId,
        flutterLocalNotificationsPlugin,
      );
    } catch (e) {
      debugPrint('Rating check error: $e');
    }
  });
}

Future<void> _maybeShowRatingNotification(
  String userId,
  FlutterLocalNotificationsPlugin plugin,
) async {
  final prefs = await SharedPreferences.getInstance();
  bool enabled = prefs.getBool('rating_enabled') ?? true;
  int hour = prefs.getInt('rating_hour') ?? 20;
  int minute = prefs.getInt('rating_minute') ?? 0;
  String lastShown = prefs.getString('last_rating_shown') ?? "";
  String lastSubmitted = prefs.getString('last_rating_submitted') ?? "";
  String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  if (!enabled) return;
  if (lastSubmitted == today) return; // user already submitted today
  if (lastShown == today) return; // notification already shown today

  DateTime now = DateTime.now();
  if (now.hour == hour && now.minute == minute) {
    final androidDetails = AndroidNotificationDetails(
      'rating_channel',
      'Daily Rating',
      importance: Importance.high,
      priority: Priority.high,
    );
    final details = NotificationDetails(android: androidDetails);

    await plugin.show(
      999,
      'How was your stress today?',
      'Tap to rate 0–5',
      details,
      payload: 'stress_rating',
    );

    await prefs.setString('last_rating_shown', today);
  }
}

Future<void> _collectAndSync(String userId) async {
  // A. LOCATION
  try {
    // FIX: Updated to new LocationSettings API
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    Map<String, dynamic> locData = {
      'lat': position.latitude,
      'lng': position.longitude,
      'speed': position.speed,
      'accuracy': position.accuracy,
    };
    await _sendData(userId, "Location", jsonEncode(locData));
  } catch (e) {
    debugPrint("Location Error: $e");
  }

  // B. CALL LOGS (Last 24 hours summary)
  try {
    int now = DateTime.now().millisecondsSinceEpoch;
    Iterable<CallLogEntry> entries = await CallLog.query(
      dateFrom: now - (24 * 60 * 60 * 1000),
    );
    Map<String, int> callStats = {
      'incoming': entries.where((c) => c.callType == CallType.incoming).length,
      'outgoing': entries.where((c) => c.callType == CallType.outgoing).length,
      'missed': entries.where((c) => c.callType == CallType.missed).length,
      'rejected': entries.where((c) => c.callType == CallType.rejected).length,
    };
    await _sendData(userId, "Call_Stats_24h", jsonEncode(callStats));
  } catch (e) {
    debugPrint("Call Log Error: $e");
  }

  // C. SMS (Daily Count)
  try {
    final SmsQuery query = SmsQuery();

    // FIX: Updated Enum to lowercase (inbox, sent)
    List<SmsMessage> inbox = await query.querySms(kinds: [SmsQueryKind.inbox]);
    List<SmsMessage> sent = await query.querySms(kinds: [SmsQueryKind.sent]);

    int receivedToday = inbox.where((m) => _isToday(m.date)).length;
    int sentToday = sent.where((m) => _isToday(m.date)).length;

    Map<String, int> smsData = {
      "received_today": receivedToday,
      "sent_today": sentToday,
      "total_today": receivedToday + sentToday,
    };

    await _sendData(userId, "SMS_Activity", jsonEncode(smsData));
  } catch (e) {
    debugPrint("SMS Error: $e");
  }

  // D. APP USAGE
  try {
    DateTime end = DateTime.now();
    DateTime start = end.subtract(const Duration(minutes: 15));
    List<UsageInfo> usage = await UsageStats.queryUsageStats(start, end);

    // Filter apps used for more than 1 second to reduce spam
    Map<String, String> appUsage = {};
    for (var u in usage) {
      int totalTime = int.parse(u.totalTimeInForeground ?? "0");
      if (totalTime > 1000) {
        appUsage[u.packageName ?? "unknown"] =
            "${(totalTime / 1000).toStringAsFixed(1)}s";
      }
    }
    if (appUsage.isNotEmpty) {
      await _sendData(userId, "App_Usage_15m", jsonEncode(appUsage));
    }
  } catch (e) {
    debugPrint("Usage Stats Error: $e");
  }
}

Future<void> _sendData(String userId, String dataType, String value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    String currentId = prefs.getString('user_id') ?? userId;
    await BackgroundServiceHelper.sendToSheet(currentId, dataType, value);
    debugPrint("Data Sent: $dataType");
  } catch (e) {
    debugPrint("Network Error: $e");
  }
}

bool _isToday(DateTime? date) {
  if (date == null) return false;
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}
