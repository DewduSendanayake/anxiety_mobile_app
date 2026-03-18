import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  /// Called when the user taps a notification.
  /// Receives the payload string (e.g. 'ema_morning', 'gad7').
  static void Function(String? payload)? onNotificationClick;

  static Future<void> init({void Function(String? payload)? onPayload}) async {
    onNotificationClick = onPayload;

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
    );

    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Fire both the global payload handler and any local callback
        if (onNotificationClick != null) {
          onNotificationClick!(response.payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );
  }

  static Future<void> showEmaNotification({
    required int id,
    required String title,
    required String payload,
  }) async {
    await plugin.show(
      id,
      title,
      'How anxious do you feel right now? Tap to rate (1–5)',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ema_channel',
          'Daily Check-ins',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> showGad7Notification() async {
    await plugin.show(
      904,
      '📋 Weekly Assessment Due',
      'Please complete your weekly GAD-7 anxiety questionnaire.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ema_channel',
          'Daily Check-ins',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'gad7',
    );
  }
}

@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  // Background tap handler — no UI context available here.
  // The payload is picked up when the app opens via initState checks.
  debugPrint('Background notification tapped: ${response.payload}');
}
