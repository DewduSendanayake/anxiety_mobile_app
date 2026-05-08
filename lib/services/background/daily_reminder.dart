import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../ema_and_gad7.dart';
// service_config.dart intentionally unused — kept for future re-enable.

/// DailyReminder — ALL notification delivery is DISABLED.
///
/// How to re-enable later:
///   1. Uncomment the three _check* calls inside checkAndShow().
///   2. In background_service.dart, add back the 1-minute Timer.periodic
///      that calls DailyReminder.checkAndShow(plugin).
///   3. Remove the early return at the top of checkAndShow().
class DailyReminder {
  /// Entry point called by the background service.
  /// Currently a no-op — returns immediately without scheduling anything.
  static Future<void> checkAndShow(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    // ── NOTIFICATIONS DISABLED ──
    // Returning here prevents any notification from being shown.
    // The background_service.dart no longer calls this at all, so this
    // guard is a belt-and-suspenders safety net.
    debugPrint("DailyReminder: notifications disabled — no-op.");
    return;

    // ── Re-enable block (currently unreachable) ──
    // final prefs = await SharedPreferences.getInstance();
    // final now   = DateTime.now();
    // final today = DateFormat('yyyy-MM-dd').format(now);
    // final bool enabled = prefs.getBool('rating_enabled') ?? true;
    // if (!enabled) return;
    //
    // await _checkPeriod(prefs, plugin, now, today, 'morning');
    // await _checkPeriod(prefs, plugin, now, today, 'afternoon');
    // await _checkPeriod(prefs, plugin, now, today, 'evening');
    // await _checkWeeklyGad7(prefs, plugin, now, today);
    // await _checkWeeklyPss10(prefs, plugin, now, today);
  }

  // ── PRESERVED HELPERS — not called while notifications are disabled ──

  static Future<void> _checkPeriod(
    SharedPreferences prefs,
    FlutterLocalNotificationsPlugin plugin,
    DateTime now,
    String today,
    String period,
  ) async {
    final int targetHour = prefs.getInt('ema_${period}_hour') ??
        (period == 'morning' ? 9 : period == 'afternoon' ? 14 : 20);
    final int targetMinute = prefs.getInt('ema_${period}_minute') ?? 0;

    final String lastSubmitted = prefs.getString('ema_submitted_$period') ?? "";
    if (lastSubmitted == today) return;

    final int nowMinutes = now.hour * 60 + now.minute;
    final int targetMinutes = targetHour * 60 + targetMinute;
    const int activeWindowMinutes = 240;

    if (nowMinutes >= targetMinutes &&
        nowMinutes < (targetMinutes + activeWindowMinutes)) {
      final int lastTs = prefs.getInt('ema_reminder_ts_$period') ?? 0;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;

      if (nowMs - lastTs > (55 * 60 * 1000)) {
        final String? title = {
          'morning': '☀️ Morning Check-in',
          'afternoon': '🌤️ Afternoon Check-in',
          'evening': '🌙 Evening Check-in',
        }[period];

        await plugin.show(
          _getNotificationId(period),
          title,
          'Tap to complete your check-in',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'ema_channel',
              'Daily Check-ins',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          payload: 'ema_rating_$period',
        );

        await prefs.setInt('ema_reminder_ts_$period', nowMs);
      }
    }
  }

  static Future<void> _checkWeeklyGad7(
    SharedPreferences prefs,
    FlutterLocalNotificationsPlugin plugin,
    DateTime now,
    String today,
  ) async {
    if (!await isGad7DueThisWeek()) return;
    if (now.hour < 9 || now.hour > 21) return;

    final int lastTs = prefs.getInt('gad7_reminder_ts') ?? 0;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    if (nowMs - lastTs > (4 * 60 * 60 * 1000)) {
      await plugin.show(
        700,
        '📋 Weekly GAD-7',
        'Your weekly anxiety questionnaire is ready.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gad7_channel',
            'Weekly Assessments',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: 'gad7_weekly',
      );
      await prefs.setInt('gad7_reminder_ts', nowMs);
    }
  }

  static Future<void> _checkWeeklyPss10(
    SharedPreferences prefs,
    FlutterLocalNotificationsPlugin plugin,
    DateTime now,
    String today,
  ) async {
    if (now.hour < 9 || now.hour > 21) return;
    if (prefs.getString('pss10_notified_today') == today) return;

    if (await isPss10DueThisWeek()) {
      await plugin.show(
        800,
        '📋 Monthly PSS-10',
        'Your monthly stress scale is ready.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'pss_channel',
            'Monthly Assessments',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: 'pss10_monthly',
      );
      await prefs.setString('pss10_notified_today', today);
    }
  }

  static int _getNotificationId(String period) {
    if (period == 'morning') return 901;
    if (period == 'afternoon') return 902;
    return 903;
  }
}