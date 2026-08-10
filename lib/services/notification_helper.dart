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

  static AndroidFlutterLocalNotificationsPlugin? get _androidPlugin => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

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

      // Existing installations may have completed onboarding before Android
      // introduced or the app requested POST_NOTIFICATIONS. Check again here
      // so an upgrade cannot silently disable critical early-warning alerts.
      await ensurePermissions();

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

  static Future<bool> ensurePermissions() async {
    try {
      final android = _androidPlugin;
      if (android == null) return true;
      final enabled = await android.areNotificationsEnabled();
      if (enabled == true) return true;
      return await android.requestNotificationsPermission() ?? false;
    } catch (error, stack) {
      debugPrint('Could not check notification permission: $error');
      debugPrint('$stack');
      return false;
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
      'Tap to rate it from 0 to 5',
      details,
      payload: 'stress_rating',
    );
  }

  static Future<bool> showAnxietyAlert({
    required String eventId,
    required int leadMinutes,
  }) async {
    if (!await ensurePermissions()) {
      debugPrint('Anxiety alert not shown: notification permission denied.');
      return false;
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'anxiety_alerts',
        'Anxiety check-ins',
        channelDescription: 'Check-ins when your anxiety level may be rising',
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

    try {
      await plugin.show(
        eventId.hashCode & 0x7fffffff,
        leadMinutes <= 0
            ? 'Your anxiety level may be high right now'
            : 'Your anxiety level may rise soon',
        leadMinutes <= 0
            ? 'Aura noticed a high reading. Do you feel anxious right now?'
            : 'It may rise in about $leadMinutes minutes. Do you notice anxiety building?',
        details,
        payload: 'anxiety_checkin:$eventId',
      );
      return true;
    } catch (error, stack) {
      debugPrint('Could not show anxiety alert: $error');
      debugPrint('$stack');
      return false;
    }
  }

  static Future<void> showAnxietyFollowup({
    required String eventId,
    required bool signalsImproved,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'anxiety_alerts',
        'Anxiety check-ins',
        channelDescription: 'Check-ins when your anxiety level may be rising',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
    );
    await plugin.show(
      (eventId.hashCode + 1) & 0x7fffffff,
      'How are you feeling now?',
      signalsImproved
          ? 'Your readings went down. Tap to tell us what helped.'
          : 'Tap for a quick follow-up and tell us what you tried.',
      details,
      payload: 'anxiety_checkin:$eventId',
    );
  }
}
