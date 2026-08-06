import 'user_manager.dart';
import 'chest_strap_service.dart';

/// Routes incoming chest strap data to the active user's SensorManager.
class BleBridge {
  static final BleBridge _instance = BleBridge._internal();
  factory BleBridge() => _instance;
  BleBridge._internal();

  /// Call this to wire up the ChestStrapService data callback
  /// to the active user's SensorManager.
  void wireChestStrap() {
    ChestStrapService().onDataReceived = (reading) {
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
    };
  }
}