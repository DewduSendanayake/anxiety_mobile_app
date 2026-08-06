import 'dart:async';
import 'user_manager.dart';
import 'chest_strap_service.dart';

/// Routes incoming chest strap data to the active user's SensorManager.
class BleBridge {
  static final BleBridge _instance = BleBridge._internal();
  factory BleBridge() => _instance;
  BleBridge._internal();

  StreamSubscription<ChestStrapReading>? _subscription;

  /// Call this to wire up the ChestStrapService data stream
  /// to the active user's SensorManager.
  void wireChestStrap() {
    _subscription?.cancel();
    
    _subscription = ChestStrapService().readingsStream.listen((reading) {
      if (!reading.isWorn) {
        // Strap is connected over BLE but user is not wearing it on body
        return;
      }
      if (UserManager().isLoggedIn && UserManager().sensorManager != null) {
        UserManager().sensorManager!.addLiveChestStrapData(
          reading.meanHR,
          reading.meanRR,
          reading.sdnn,
          reading.rmssd,
          reading.meanBR,
          reading.stdBR,
          reading.meanTemp,
          reading.stdTemp,
          reading.meanAccMag,
          reading.stdAccMag,
        );
      } else {
        print('BLE Router Warning: Chest strap data dropped because no active user session exists.');
      }
    });
  }

  /// Cancels the subscription to free resources on logout
  void unwireChestStrap() {
    _subscription?.cancel();
    _subscription = null;
  }
}