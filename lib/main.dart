import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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

import 'package:shared_preferences/shared_preferences.dart';

import 'ema_and_gad7.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmaRatingSheet(timePeriod: period),
    );
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const Gad7Screen()));
    return;
  }

  if (payload == 'pss10_weekly' || payload == 'pss10_monthly') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const Pss10Screen()));
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
      BackgroundServiceHelper.retryOfflineQueue().catchError((e) {
        debugPrint('Init Queue Retry Error: $e');
      });

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
              if (connected) {
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
        if (userId != null && userId.isNotEmpty) {
          // Restore the physiological session on every cold launch. Without
          // this, BLE packets still reach the dashboard but never enter the
          // 60-second /ingest pipeline.
          UserManager().login(userId);
          await bg.initializeService();
          shouldStartBackgroundService = true;
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
        _routeNotificationPayload(NotificationHelper.consumeLaunchPayload());
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
    final userId = prefs.getString('user_id');
    final profileComplete = prefs.getBool('profile_complete') ?? false;
    final calibrationComplete = prefs.getBool('calibration_complete') ?? false;

    if (!consentAccepted) {
      return const InformedConsentPage();
    } else if (userId == null || userId.isEmpty) {
      return const LoginPage();
    } else if (!profileComplete) {
      return const ProfilePage();
    } else if (!calibrationComplete) {
      return BaselineCalibrationPage(userId: userId);
    } else {
      return MainNavigationPage(userId: userId);
    }
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
