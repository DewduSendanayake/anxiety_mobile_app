import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'theme/app_theme.dart';
import 'pages/informed_consent_page.dart';
import 'pages/login_page.dart';

import 'pages/main_navigation_page.dart';
import 'profile_page.dart';
import 'background_service_helper.dart';
import 'services/notification_helper.dart';
import 'services/background/background_service.dart' as bg;
import 'package:shared_preferences/shared_preferences.dart';
import 'ema_and_gad7.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void _handleNotificationTap(String? payload) {
  if (payload == null || payload.isEmpty) return;

  final context = navigatorKey.currentContext;
  if (context == null) {
    debugPrint('Notification tap ignored: no navigator context yet. payload=$payload');
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

  if (payload == 'gad7_weekly') {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const Gad7Screen()),
    );
    return;
  }

  if (payload == 'pss10_weekly' || payload == 'pss10_monthly') {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const Pss10Screen()),
    );
    return;
  }
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
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await NotificationHelper.init();
      NotificationHelper.onNotificationClick = _handleNotificationTap;
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
      Connectivity().onConnectivityChanged.listen((event) async {
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
      }, onError: (e) {
        debugPrint('Connectivity stream error: $e');
      });
    } catch (e) {
      debugPrint('Connectivity Listener Error: $e');
    }

    // 3. UI System Styling (Edge-to-edge)
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    // 4. Initialize Background Service (Only if User ID exists)
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId != null && userId.isNotEmpty) {
        await bg.initializeService();
      } else {
        debugPrint('Background Service: No User ID, skipping initialization.');
      }
    } catch (e) {
      debugPrint('Background Service Init Error: $e');
    }

    runApp(const ResearchApp());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationTap(NotificationHelper.consumeLaunchPayload());
    });
  }, (error, stack) {
    // Zone-level fallback — catches anything that slips through.
    debugPrint('🔴 Uncaught zone error: $error');
    debugPrint('$stack');
  });
}

class ResearchApp extends StatelessWidget {
  const ResearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Aura - Mindfulness Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashRouter(),
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

    if (!consentAccepted) {
      return const InformedConsentPage();
    } else if (userId == null || userId.isEmpty) {
      return const LoginPage();
    } else if (!profileComplete) {
      return const ProfilePage();
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
        return snapshot.data ?? const LoginPage();
      },
    );
  }
}
