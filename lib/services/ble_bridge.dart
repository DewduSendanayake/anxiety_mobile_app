import 'user_manager.dart';

class BleBridge {
  // This is the single switchboard instance for the app
  static final BleBridge _instance = BleBridge._internal();
  factory BleBridge() => _instance;
  BleBridge._internal();

  // ROUTE 1: ECG Data Router
  // Call this inside your Bluetooth plugin's ECG characteristic listener
  void routeIncomingEcg(double rawValue) {
    // Check if a user is logged in and tracking before doing anything
    if (UserManager().isLoggedIn && UserManager().sensorManager != null) {
      // Pass the value directly to the active sensor manager
      UserManager().sensorManager!.onEcgDataReceived(rawValue);
    } else {
      print('BLE Router Warning: ECG data dropped because no active user session exists.');
    }
  }

  // ROUTE 2: Respiration Data Router
  // Call this inside your Bluetooth plugin's Breathing characteristic listener
  void routeIncomingResp(double rawValue) {
    if (UserManager().isLoggedIn && UserManager().sensorManager != null) {
      UserManager().sensorManager!.onRespDataReceived(rawValue);
    }
  }

  // ROUTE 3: Temperature Data Router
  // Call this inside your Bluetooth plugin's Temp characteristic listener
  void routeIncomingTemp(double rawValue) {
    if (UserManager().isLoggedIn && UserManager().sensorManager != null) {
      UserManager().sensorManager!.onTempDataReceived(rawValue);
    }
  }

  // ROUTE 4: Motion/Accelerometer Data Router
  // Call this inside your Bluetooth plugin's Motion characteristic listener
  void routeIncomingMotion(double x, double y, double z) {
    if (UserManager().isLoggedIn && UserManager().sensorManager != null) {
      UserManager().sensorManager!.onAccelerometerDataReceived(x, y, z);
    }
  }
}