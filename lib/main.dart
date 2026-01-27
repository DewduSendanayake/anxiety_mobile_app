import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_service.dart';
import 'background_service_helper.dart';

// --- THEME CONSTANTS ---
const Color kPrimaryColor = Color(0xFF00695C); // Medical Teal
const Color kSecondaryColor = Color(0xFFB2DFDB); // Soft Teal
const Color kAccentColor = Color(0xFF009688);
const Color kSurfaceColor = Colors.white;
const Color kBackgroundColor = Color(0xFFF5F7FA); // Light Grey-Blue

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set status bar color for premium feel
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: ResearchApp()),
  );
}

class ResearchApp extends StatelessWidget {
  const ResearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anxiety Research',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBackgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimaryColor,
          primary: kPrimaryColor,
          secondary: kAccentColor,
          surface: kSurfaceColor,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBackgroundColor,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: Colors.black87),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryColor,
            foregroundColor: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.all(20),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _idController = TextEditingController();
  bool _permissionsGranted = false;
  bool _isLoading = false;

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    if (!kIsWeb && Platform.isAndroid) {
      await [
        Permission.locationAlways,
        Permission.phone,
        Permission.sms,
        Permission.notification,
      ].request();

      var batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }

      bool isUsageGranted = await UsageStats.checkUsagePermission() ?? false;
      if (!isUsageGranted) {
        await UsageStats.grantUsagePermission();
      }
    }

    // Simulate a check/delay for better UX
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _permissionsGranted = true;
      _isLoading = false;
    });
  }

  Future<void> _login() async {
    if (_idController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your Participant ID"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', _idController.text);
    await initializeService();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- LOGO & HEADER ---
                const Icon(
                  Icons.health_and_safety,
                  size: 64,
                  color: kPrimaryColor,
                ),
                const SizedBox(height: 20),
                const Text(
                  "Research Companion",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Secure Anxiety Monitoring System",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 40),

                // --- STEP 1: PERMISSIONS CARD ---
                _buildCard(
                  title: "1. System Configuration",
                  isActive: !_permissionsGranted,
                  child: Column(
                    children: [
                      Text(
                        "To ensure accurate data collection without interruptions, this app requires background access permissions.",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _permissionsGranted
                              ? null
                              : _requestPermissions,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _permissionsGranted
                                      ? Icons.check_circle
                                      : Icons.shield_moon,
                                ),
                          label: Text(
                            _permissionsGranted
                                ? "Configuration Complete"
                                : "Grant Secure Access",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _permissionsGranted
                                ? Colors.green
                                : kPrimaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // --- STEP 2: LOGIN CARD ---
                Opacity(
                  opacity: _permissionsGranted ? 1.0 : 0.5,
                  child: _buildCard(
                    title: "2. Participant Identification",
                    isActive: _permissionsGranted,
                    child: Column(
                      children: [
                        TextField(
                          controller: _idController,
                          enabled: _permissionsGranted,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Enter Participant ID",
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _permissionsGranted ? _login : null,
                            child: const Text("Initialize Session"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                const Text(
                  "Your data is encrypted and used solely for research purposes.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required Widget child,
    required bool isActive,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: isActive
            ? Border.all(color: kPrimaryColor.withOpacity(0.3))
            : null,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.black87 : Colors.grey,
            ),
          ),
          const Divider(height: 24),
          child,
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  String _statusMessage = "Ready to record";
  double _currentPressure = 0.0;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Monitoring Dashboard"),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // --- STATUS CARD ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "System Active & Recording",
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // --- INSTRUCTION TEXT ---
            const Text(
              "Anxiety Event Recorder",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "If you feel anxious, press and hold the sensor below. Vary your pressure to match the intensity.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
            ),

            const SizedBox(height: 40),

            // --- INTERACTIVE SENSOR PAD ---
            Listener(
              onPointerDown: (event) => _handleTouch(event, true),
              onPointerMove: (event) => _handleTouch(event, true),
              onPointerUp: (event) => _handleTouch(event, false),
              onPointerCancel: (event) => _handleTouch(event, false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isPressed
                        ? [kPrimaryColor, kAccentColor]
                        : [Colors.white, Colors.grey.shade100],
                  ),
                  boxShadow: [
                    // Outer Glow
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(_isPressed ? 0.4 : 0.1),
                      blurRadius: _isPressed ? 30 : 20,
                      spreadRadius: _isPressed ? 5 : 0,
                      offset: const Offset(0, 10),
                    ),
                    // Inner Shadow for depth
                    if (!_isPressed)
                      BoxShadow(
                        color: Colors.white,
                        blurRadius: 10,
                        offset: const Offset(-5, -5),
                      ),
                  ],
                  border: Border.all(
                    color: _isPressed ? kPrimaryColor : Colors.grey.shade200,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.fingerprint,
                      size: 60,
                      color: _isPressed
                          ? Colors.white
                          : kPrimaryColor.withOpacity(0.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isPressed
                          ? "${(_currentPressure * 100).toInt()}% Intensity"
                          : "Press Here",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _isPressed ? Colors.white : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // --- FOOTER ---
            Text(
              "ID: ${BackgroundServiceHelper.getCachedId()}",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTouch(PointerEvent event, bool isPressed) async {
    setState(() {
      _isPressed = isPressed;
      _currentPressure = isPressed ? event.pressure : 0.0;
    });

    if (isPressed) {
      final prefs = await SharedPreferences.getInstance();
      String uid = prefs.getString('user_id') ?? "Unknown";

      // Send to helper
      await BackgroundServiceHelper.sendToSheet(
        uid,
        "Touch_Event",
        "Pressure:${event.pressure.toStringAsFixed(2)}",
      );
    }
  }
}
