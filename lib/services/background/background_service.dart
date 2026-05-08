import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';

import '../background_service_helper.dart';
import 'service_config.dart';
import 'data_collector.dart';
import 'sensor_listener.dart';
// DailyReminder is intentionally NOT imported — notifications are disabled.

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    ServiceConfig.channelId,
    ServiceConfig.channelName,
    description: 'Running background research tasks',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  if (androidPlugin != null) {
    await androidPlugin.createNotificationChannel(channel);
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'ema_channel',
        'Daily Check-ins',
        description: 'Scheduled mood and anxiety ratings',
        importance: Importance.high,
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'gad7_channel',
        'Weekly Assessments',
        description: 'Weekly GAD-7 clinical questionnaires',
        importance: Importance.high,
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'pss_channel',
        'Monthly Assessments',
        description: 'Monthly Perceived Stress Scale (PSS-10) assessments',
        importance: Importance.high,
      ),
    );
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: ServiceConfig.channelId,
      initialNotificationTitle: 'Research Active',
      initialNotificationContent: 'Monitoring touch patterns...',
      foregroundServiceNotificationId: ServiceConfig.notificationId,
      autoStartOnBoot: true,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // ── CRITICAL: mark as background isolate BEFORE any sendToSheet call ──
  // This must be the very first thing so every subsequent queue write goes
  // to 'offline_queue_bg' and does not collide with the UI isolate's
  // 'offline_queue_main'.
  BackgroundServiceHelper.isMainIsolate = false;

  debugPrint("🔋 Background Service: onStart beginning...");

  final prefs = await SharedPreferences.getInstance();

  // Force-reload so the background isolate sees the user_id written by the
  // UI isolate (SharedPreferences are cached per-isolate).
  await prefs.reload();

  final String? userId = prefs.getString('user_id');

  if (userId == null || userId.isEmpty) {
    debugPrint("Background Service: No User ID — stopping.");
    service.stopSelf();
    return;
  }

  // ── 1. Connectivity listener — upload queued items when network returns ──
  try {
    await BackgroundServiceHelper.retryOfflineQueue();

    Connectivity().onConnectivityChanged.listen((event) async {
      final bool hasConnection = event is List
          ? (event as List).any((r) => r != ConnectivityResult.none)
          : event != ConnectivityResult.none;

      if (hasConnection) {
        debugPrint("🌐 Connectivity restored — retrying sync...");
        await BackgroundServiceHelper.retryOfflineQueue();
      }
    });
  } catch (e) {
    debugPrint('Connectivity Setup Error: $e');
  }

  // ── 2. Foreground / background service control messages ──
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
  }
  service.on('stopService').listen((_) => service.stopSelf());

  // ── 3. Battery monitor ──────────────────────────────────────────────────
  // BUG FIX: the original code only recorded battery level when the battery
  // *state* changed (charging ↔ discharging).  While the phone sits idle and
  // fully discharging, onBatteryStateChanged never fires, so last_battery_level
  // stays at 0.  DataCollector.collectAndSync() then reads this stale 0 and
  // sends "Battery_Status: 0%" to the sheet.
  //
  // Fix: DataCollector now reads battery level directly (see data_collector.dart).
  // Here we keep the critical-battery warning which DOES need the state event.
  try {
    final battery = Battery();
    battery.onBatteryStateChanged.listen((BatteryState state) async {
      try {
        final int level = await battery.batteryLevel;
        // Keep prefs in sync for any other code that reads it.
        await prefs.setInt('last_battery_level', level);

        if (level <= 15 && state == BatteryState.discharging) {
          await BackgroundServiceHelper.sendToSheet(
            userId,
            "Critical_Battery_Warning",
            "Level: $level%",
            immediate: true,   // send right away — device may die soon
          );
        }
      } catch (e) {
        debugPrint("Battery Event Error: $e");
      }
    });
  } catch (e) {
    debugPrint("Battery Monitor Setup Error: $e");
  }

  // ── 4. Real-time sensor listeners (screen on/off, accelerometer) ────────
  try {
    final sensorListener = SensorListener();
    sensorListener.startListening(userId);
  } catch (e) {
    debugPrint("SensorListener Setup Error: $e");
  }

  // ── 5. Periodic data collection (every 15 minutes) ──────────────────────
  // Collect immediately on start so there is no 15-minute gap at boot.
  unawaited(DataCollector.collectAndSync(userId).catchError(
    (e) => debugPrint("Initial DataCollector Error: $e"),
  ));

  Timer.periodic(const Duration(minutes: 15), (_) async {
    debugPrint("⏰ Periodic Task: 15 m collection...");
    try {
      await DataCollector.collectAndSync(userId);
    } catch (e) {
      debugPrint("Periodic Timer Error: $e");
    }
  });

  // ── NOTIFICATIONS DISABLED ──────────────────────────────────────────────
  // The 1-minute DailyReminder timer has been removed entirely.
  // DailyReminder.checkAndShow() already returns early, but running a timer
  // every minute with no effect wastes CPU and can interfere with battery
  // optimisation.  Re-add the timer here when notifications are re-enabled.
  debugPrint("🔕 Notification scheduling is disabled — no reminder timer started.");
}

// Silence the unawaited-future lint for fire-and-forget calls.
void unawaited(Future<void> future) {}