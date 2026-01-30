import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  // Called when the user taps the notification
  static VoidCallback? onNotificationClick;

  static Future<void> init() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
    );

    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Route to the app via callback
        if (onNotificationClick != null) onNotificationClick!();
      },
    );
  }

  static Future<void> showRatingNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'rating_channel',
          'Daily Rating',
          importance: Importance.high,
          priority: Priority.high,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await plugin.show(
      999,
      'How was your stress today?',
      'Tap to rate 0–5',
      details,
      payload: 'stress_rating',
    );
  }
}
