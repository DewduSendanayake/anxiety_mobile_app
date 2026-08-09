import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  static String? _launchPayload;
  static const String anxietyYesAction = 'anxiety_yes';
  static const String anxietyNoAction = 'anxiety_no';

  // Called when the user taps a notification body or action button.
  static void Function(NotificationResponse)? onNotificationResponse;

  static Future<void> init({
    DidReceiveBackgroundNotificationResponseCallback? backgroundCallback,
  }) async {
    try {
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      const InitializationSettings initSettings = InitializationSettings(
        android: androidInit,
      );

      await plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          onNotificationResponse?.call(response);
        },
        onDidReceiveBackgroundNotificationResponse: backgroundCallback,
      );

      // Capture payload when app is opened by tapping a notification
      // from a terminated state.
      final launchDetails = await plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _launchPayload = launchDetails?.notificationResponse?.payload;
      }
    } catch (e, st) {
      // Don't rethrow — log and allow app to continue.
      debugPrint('Notification plugin init failed: $e');
      debugPrint('$st');
    }
  }

  static String? consumeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  static Future<void> showRatingNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'rating_channel',
          'Daily Rating',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: false,
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

  static Future<void> showAnxietyAlert({required String eventId}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'anxiety_alerts',
        'Anxiety check-ins',
        channelDescription:
            'Heads-up check-ins after physiological signals stay high',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.reminder,
        actions: [
          AndroidNotificationAction(
            anxietyYesAction,
            'Yes',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            anxietyNoAction,
            'No',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
    );

    await plugin.show(
      eventId.hashCode & 0x7fffffff,
      'Quick anxiety check-in',
      'Your signals have stayed high for 3 minutes. Do you feel anxious?',
      details,
      payload: 'anxiety_checkin:$eventId',
    );
  }

  static Future<void> showAnxietyFollowup({
    required String eventId,
    required bool signalsImproved,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'anxiety_alerts',
        'Anxiety check-ins',
        channelDescription:
            'Heads-up check-ins after physiological signals stay high',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
    );
    await plugin.show(
      (eventId.hashCode + 1) & 0x7fffffff,
      'How are you feeling now?',
      signalsImproved
          ? 'Your signals decreased. Tap to tell us what helped.'
          : 'Tap for a quick follow-up and tell us what you tried.',
      details,
      payload: 'anxiety_checkin:$eventId',
    );
  }
}
