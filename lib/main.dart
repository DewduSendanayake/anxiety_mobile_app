import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'theme/app_theme.dart';
import 'pages/login_page.dart';
import 'background_service_helper.dart';
import 'services/notification_helper.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await NotificationHelper.init();
  } catch (e, st) {
    debugPrint('Notification init error: $e');
    debugPrint('$st');
  }

  // 1. Queue Retry (Offline Architecture)
  try {
    await BackgroundServiceHelper.retryOfflineQueue();
  } catch (e) {
    debugPrint('Init Queue Retry Error: $e');
  }

  // 2. Connectivity Listener (Auto-Upload when internet returns)
  try {
    Connectivity().onConnectivityChanged.listen((result) async {
      if (result != ConnectivityResult.none) {
        await BackgroundServiceHelper.retryOfflineQueue();
      }
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

  runApp(const ResearchApp());
}

class ResearchApp extends StatelessWidget {
  const ResearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Mindful Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const LoginPage(),
    );
  }
}
