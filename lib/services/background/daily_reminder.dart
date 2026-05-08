import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../ema_and_gad7.dart';

/// DailyReminder — all study notifications.
///
///  • 3 EMA check-ins/day at user-configured times (4-hour window each,
///    re-fires every 55 min until submitted or window closes).
///  • GAD-7 weekly questionnaire (re-fires every 4 h until done).
///  • PSS-10 weekly questionnaire (once per day reminder).
///
/// Called from a Timer.periodic(Duration(minutes: 1)) in background_service.dart.
class DailyReminder {
  static Future<void> checkAndShow(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // Master kill-switch — user can disable all check-ins from Settings.
    final bool enabled = prefs.getBool('rating_enabled') ?? true;
    if (!enabled) {
      debugPrint("DailyReminder: check-ins disabled by user.");
      return;
    }

    final DateTime now   = DateTime.now();
    final String   today = DateFormat('yyyy-MM-dd').format(now);

    debugPrint(
      "DailyReminder: tick ${now.hour}:${now.minute.toString().padLeft(2, '0')}",
    );

    // ── 1. EMA check-ins (3 × daily) ──────────────────────────────────────
    await _checkPeriod(prefs, plugin, now, today, 'morning');
    await _checkPeriod(prefs, plugin, now, today, 'afternoon');
    await _checkPeriod(prefs, plugin, now, today, 'evening');

    // ── 2. Clinical questionnaires ─────────────────────────────────────────
    await _checkWeeklyGad7(prefs, plugin, now, today);
    await _checkWeeklyPss10(prefs, plugin, now, today);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EMA PERIOD
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _checkPeriod(
    SharedPreferences prefs,
    FlutterLocalNotificationsPlugin plugin,
    DateTime now,
    String today,
    String period,
  ) async {
    // Already submitted today — nothing to do.
    if (prefs.getString('ema_submitted_$period') == today) return;

    // User-configured target time.
    final int targetHour = prefs.getInt('ema_${period}_hour') ??
        (period == 'morning' ? 9 : period == 'afternoon' ? 14 : 20);
    final int targetMinute = prefs.getInt('ema_${period}_minute') ?? 0;

    final int nowMinutes    = now.hour * 60 + now.minute;
    final int targetMinutes = targetHour * 60 + targetMinute;

    // Active window = target time + 4 hours.
    const int windowMinutes = 240;
    if (nowMinutes < targetMinutes ||
        nowMinutes >= targetMinutes + windowMinutes) {
      return;
    }

    // Throttle: at most one reminder per 55 minutes.
    final int lastTs = prefs.getInt('ema_reminder_ts_$period') ?? 0;
    final int nowMs  = DateTime.now().millisecondsSinceEpoch;
    if ((nowMs - lastTs) < 55 * 60 * 1000) return;

    final titles = {
      'morning'  : '☀️ Morning Check-in',
      'afternoon': '🌤️ Afternoon Check-in',
      'evening'  : '🌙 Evening Check-in',
    };
    final bodies = {
      'morning'  : 'Good morning! Take a moment to rate how you feel today.',
      'afternoon': 'Midday check-in — how are you feeling right now?',
      'evening'  : 'Evening check-in — wrap up your day with a quick rating.',
    };

    debugPrint("DailyReminder: ▶ EMA [$period]");

    await plugin.show(
      _idForPeriod(period),
      titles[period],
      bodies[period],
      NotificationDetails(
        android: AndroidNotificationDetails(
          'ema_channel',
          'Daily Check-ins',
          channelDescription: 'Scheduled mood and anxiety ratings',
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFF5E60CE),
        ),
      ),
      payload: 'ema_rating_$period',
    );

    await prefs.setInt('ema_reminder_ts_$period', nowMs);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WEEKLY GAD-7
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _checkWeeklyGad7(
    SharedPreferences prefs,
    FlutterLocalNotificationsPlugin plugin,
    DateTime now,
    String today,
  ) async {
    if (now.hour < 9 || now.hour > 21) return;
    if (!await isGad7DueThisWeek()) return;

    final int lastTs = prefs.getInt('gad7_reminder_ts') ?? 0;
    final int nowMs  = DateTime.now().millisecondsSinceEpoch;
    if ((nowMs - lastTs) < 4 * 60 * 60 * 1000) return;

    debugPrint("DailyReminder: ▶ GAD-7 weekly");

    await plugin.show(
      700,
      '📋 Weekly Anxiety Check (GAD-7)',
      'Your 7-question weekly anxiety questionnaire is ready — about 2 minutes.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'gad7_channel',
          'Weekly Assessments',
          channelDescription: 'Weekly GAD-7 clinical questionnaires',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'gad7_weekly',
    );

    await prefs.setInt('gad7_reminder_ts', nowMs);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WEEKLY PSS-10
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _checkWeeklyPss10(
    SharedPreferences prefs,
    FlutterLocalNotificationsPlugin plugin,
    DateTime now,
    String today,
  ) async {
    if (now.hour < 9 || now.hour > 21) return;
    if (prefs.getString('pss10_notified_today') == today) return;
    if (!await isPss10DueThisWeek()) return;

    debugPrint("DailyReminder: ▶ PSS-10 weekly");

    await plugin.show(
      800,
      '📊 Weekly Stress Check (PSS-10)',
      'Your 10-question perceived stress scale is ready — about 3 minutes.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'pss_channel',
          'Monthly Assessments',
          channelDescription: 'Monthly PSS-10 stress scale assessments',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'pss10_monthly',
    );

    await prefs.setString('pss10_notified_today', today);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  static int _idForPeriod(String period) {
    if (period == 'morning')   return 901;
    if (period == 'afternoon') return 902;
    return 903;
  }
}