import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'pages/informed_consent_page.dart';
import 'pages/login_page.dart';
import 'pages/welcome_splash_page.dart';
import 'pages/baseline_calibration_page.dart';
import 'pages/anxiety_check_in_page.dart';

import 'pages/main_navigation_page.dart';
import 'profile_page.dart';
import 'background_service_helper.dart';
import 'services/notification_helper.dart';
import 'services/user_manager.dart';
import 'services/participant_identity_service.dart';
import 'services/anxiety_feedback_service.dart';
import 'services/background/background_service.dart' as bg;
import 'services/background/service_config.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'ema_and_gad7.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<bool> _hasCurrentConsent() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getBool('consent_accepted') ?? false) &&
      prefs.getString('consent_version') == ServiceConfig.consentVersion;
}

Future<void> _resumeExistingParticipant(String userId) async {
  UserManager().login(userId);
  await bg.initializeService();
  await bg.startBackgroundServiceIfPermitted();
  await BackgroundServiceHelper.retryOfflineQueue();
}

String _dateKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

Future<void> _openEmaCheckInIfDue(BuildContext context, String period) async {
  final prefs = await SharedPreferences.getInstance();
  final completedToday =
      prefs.getString('ema_submitted_$period') == _dateKey(DateTime.now());
  if (completedToday) {
    await NotificationHelper.cancelDailyCheckIn(period);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already completed this check-in.')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EmaRatingSheet(timePeriod: period),
  );
}

Future<void> _openWeeklyCheckInIfDue(
  BuildContext context, {
  required bool anxiety,
}) async {
  final due = anxiety ? await isGad7DueThisWeek() : await isPss10DueThisWeek();
  if (!due) {
    await NotificationHelper.cancelWeeklyCheckIn(
      anxiety ? 'anxiety' : 'stress',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already completed this weekly check-in.'),
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => anxiety ? const Gad7Screen() : const Pss10Screen(),
    ),
  );
}

void _routeNotificationPayload(String? payload) {
  if (payload == null || payload.isEmpty) return;

  final context = navigatorKey.currentContext;
  if (context == null) {
    debugPrint(
      'Notification tap ignored: no navigator context yet. payload=$payload',
    );
    return;
  }

  if (payload.startsWith('ema_rating_')) {
    final period = payload.replaceFirst('ema_rating_', '');
    unawaited(_openEmaCheckInIfDue(context, period));
    return;
  }

  if (payload.startsWith('anxiety_checkin:')) {
    final eventId = payload.substring('anxiety_checkin:'.length);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnxietyCheckInPage(eventId: eventId)),
    );
    return;
  }

  if (payload == 'gad7_weekly') {
    unawaited(_openWeeklyCheckInIfDue(context, anxiety: true));
    return;
  }

  if (payload == 'pss10_weekly' || payload == 'pss10_monthly') {
    unawaited(_openWeeklyCheckInIfDue(context, anxiety: false));
    return;
  }
}

void _handleNotificationResponse(NotificationResponse response) {
  unawaited(
    AnxietyFeedbackService.handleNotificationAction(
      actionId: response.actionId,
      payload: response.payload,
    ),
  );
  if (response.actionId == null || response.actionId!.isEmpty) {
    _routeNotificationPayload(response.payload);
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AnxietyFeedbackService.handleNotificationAction(
    actionId: response.actionId,
    payload: response.payload,
  );
}

void main() async {
  // ── Global error handlers — prevent silent crashes ──────────────────────
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('🔴 FlutterError: ${details.exceptionAsString()}');
    debugPrint('${details.stack}');
  };

  // Catch async errors that escape zones.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('🔴 PlatformDispatcher error: $error');
    debugPrint('$stack');
    return true; // Prevent the app from being terminated.
  };

  // Run the entire app inside an error zone for extra safety.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await ThemeController.instance.initialize();
      try {
        await NotificationHelper.init(
          backgroundCallback: notificationTapBackground,
        );
        NotificationHelper.onNotificationResponse = _handleNotificationResponse;
      } catch (e, st) {
        debugPrint('Notification init error: $e');
        debugPrint('$st');
      }

      // 1. Queue Retry (Offline Architecture)
      final hasCurrentConsentAtStartup = await _hasCurrentConsent();
      if (hasCurrentConsentAtStartup) {
        BackgroundServiceHelper.retryOfflineQueue().catchError((e) {
          debugPrint('Init Queue Retry Error: $e');
        });
      }

      // 2. Connectivity Listener (Auto-Upload when internet returns)
      // NOTE: connectivity_plus ^4.0 returns List<ConnectivityResult>,
      //       NOT a single ConnectivityResult. Using `dynamic` to be safe
      //       across all versions.
      try {
        Connectivity().onConnectivityChanged.listen(
          (event) async {
            try {
              final bool connected = event is List
                  ? (event as List).any((r) => r != ConnectivityResult.none)
                  : event != ConnectivityResult.none;
              if (connected && await _hasCurrentConsent()) {
                await BackgroundServiceHelper.retryOfflineQueue();
              }
            } catch (e) {
              debugPrint('Connectivity callback error: $e');
            }
          },
          onError: (e) {
            debugPrint('Connectivity stream error: $e');
          },
        );
      } catch (e) {
        debugPrint('Connectivity Listener Error: $e');
      }

      // 3. Configure Background Service (Only if User ID exists). The service
      // is deliberately started after the first frame, when Android considers
      // the app foreground-eligible and the permission can be checked safely.
      var shouldStartBackgroundService = false;
      try {
        await ParticipantIdentityService.migrateLegacyIdentity();
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('user_id');
        if (userId != null && userId.isNotEmpty && hasCurrentConsentAtStartup) {
          // Restore the physiological session on every cold launch. Without
          // this, BLE packets still reach the dashboard but never enter the
          // 60-second /ingest pipeline.
          UserManager().login(userId);
          await bg.initializeService();
          shouldStartBackgroundService = true;
        } else if (userId != null && userId.isNotEmpty) {
          FlutterBackgroundService().invoke('stopService');
          UserManager().logout();
          debugPrint(
            'Background Service: paused until the current consent version is accepted.',
          );
        } else {
          debugPrint(
            'Background Service: No User ID, skipping initialization.',
          );
        }
      } catch (e) {
        debugPrint('Background Service Init Error: $e');
      }

      runApp(const ResearchApp());

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasCurrentConsentAtStartup) {
          _routeNotificationPayload(NotificationHelper.consumeLaunchPayload());
        }
        if (shouldStartBackgroundService) {
          unawaited(bg.startBackgroundServiceIfPermitted());
        }
      });
    },
    (error, stack) {
      // Zone-level fallback — catches anything that slips through.
      debugPrint('🔴 Uncaught zone error: $error');
      debugPrint('$stack');
    },
  );
}

class ResearchApp extends StatelessWidget {
  const ResearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Aura - Mindfulness Tracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeController.instance.themeMode,
        home: const SplashRouter(),
      ),
    );
  }
}

class SplashRouter extends StatelessWidget {
  const SplashRouter({super.key});

  Future<Widget> _getHome() async {
    final prefs = await SharedPreferences.getInstance();
    final consentAccepted = prefs.getBool('consent_accepted') ?? false;
    final consentVersion = prefs.getString('consent_version');
    final userId = prefs.getString('user_id');
    final profileComplete = prefs.getBool('profile_complete') ?? false;
    final calibrationComplete = prefs.getBool('calibration_complete') ?? false;

    final Widget nextPage;
    if (userId == null || userId.isEmpty) {
      nextPage = const LoginPage();
    } else if (!profileComplete) {
      nextPage = const ProfilePage();
    } else if (!calibrationComplete) {
      nextPage = BaselineCalibrationPage(userId: userId);
    } else {
      nextPage = MainNavigationPage(userId: userId);
    }

    final hasCurrentConsent =
        consentAccepted && consentVersion == ServiceConfig.consentVersion;
    if (!hasCurrentConsent) {
      return InformedConsentPage(
        nextPage: nextPage,
        onAccepted: userId == null || userId.isEmpty
            ? null
            : () => _resumeExistingParticipant(userId),
      );
    }

    return nextPage;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _getHome(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final nextPage = snapshot.data ?? const LoginPage();
        return WelcomeSplashPage(nextPage: nextPage);
      },
    );
  }
}
