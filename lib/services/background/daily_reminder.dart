import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class DailyReminder {
  static Future<void> checkAndShow(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool enabled = prefs.getBool('rating_enabled') ?? true;
      int hour = prefs.getInt('rating_hour') ?? 20;
      int minute = prefs.getInt('rating_minute') ?? 0;
      String lastShown = prefs.getString('last_rating_shown') ?? "";
      String lastSubmitted = prefs.getString('last_rating_submitted') ?? "";
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (!enabled) return;
      if (lastSubmitted == today) return; // User already submitted
      if (lastShown == today) return; // Notification already shown

      DateTime now = DateTime.now();
      if (now.hour == hour && now.minute == minute) {
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

        await prefs.setString('last_rating_shown', today);
      }
    } catch (e) {
      debugPrint('Rating check error: $e');
    }
  }
}
