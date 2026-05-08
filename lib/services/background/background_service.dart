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
import 'daily_reminder.dart';

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
        description: 'Monthly PSS-10 assessments',
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
  BackgroundServiceHelper.isMainIsolate = false;

  debugPrint("🔋 Background Service: onStart beginning...");

  final prefs = await SharedPreferences.getInstance();
  // Force-reload so the background isolate sees the user_id set by the UI.
  await prefs.reload();

  final String? userId = prefs.getString('user_id');
  if (userId == null || userId.isEmpty) {
    debugPrint("Background Service: No User ID — stopping.");
    service.stopSelf();
    return;
  }

  // ── 1. Connectivity listener ─────────────────────────────────────────────
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

  // ── 2. Service control messages ──────────────────────────────────────────
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
  }
  service.on('stopService').listen((_) => service.stopSelf());

  // ── 3. Battery monitor ───────────────────────────────────────────────────
  try {
    final battery = Battery();
    battery.onBatteryStateChanged.listen((BatteryState state) async {
      try {
        final int level = await battery.batteryLevel;
        await prefs.setInt('last_battery_level', level);
        if (level <= 15 && state == BatteryState.discharging) {
          await BackgroundServiceHelper.sendToSheet(
            userId,
            "Critical_Battery_Warning",
            "Level: $level%",
            immediate: true,
          );
        }
      } catch (e) {
        debugPrint("Battery Event Error: $e");
      }
    });
  } catch (e) {
    debugPrint("Battery Monitor Setup Error: $e");
  }

  // ── 4. Real-time sensors ─────────────────────────────────────────────────
  try {
    final sensorListener = SensorListener();
    sensorListener.startListening(userId);
  } catch (e) {
    debugPrint("SensorListener Setup Error: $e");
  }

  // ── 5. Periodic data collection (every 15 min) ───────────────────────────
  // Collect immediately so there is no gap at boot.
  unawaited(
    DataCollector.collectAndSync(userId)
        .catchError((e) => debugPrint("Initial DataCollector Error: $e")),
  );

  Timer.periodic(const Duration(minutes: 15), (_) async {
    debugPrint("⏰ Periodic Task: 15 m collection...");
    try {
      await DataCollector.collectAndSync(userId);
    } catch (e) {
      debugPrint("Periodic Timer Error: $e");
    }
  });

  // ── 6. Background notifications plugin ──────────────────────────────────
  // The background isolate needs its own plugin instance because the one
  // created in initializeService() lives in a different isolate.
  final FlutterLocalNotificationsPlugin bgPlugin =
      FlutterLocalNotificationsPlugin();
  await bgPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
    ),
  );

  // ── 7. Daily reminder — fires every minute, manages its own throttling ───
  Timer.periodic(const Duration(minutes: 1), (_) async {
    try {
      await DailyReminder.checkAndShow(bgPlugin);
    } catch (e) {
      debugPrint("Reminder Timer Error: $e");
    }
  });

  debugPrint("✅ Background Service: fully started.");
}

// Silences the unawaited-future lint for intentional fire-and-forget calls.
void unawaited(Future<void> future) {}