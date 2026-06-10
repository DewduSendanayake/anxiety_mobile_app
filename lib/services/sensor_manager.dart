import 'dart:async';
import 'api_service.dart';

class SensorManager {
  final String userId;
  final int samplingRate;

  // These in-memory lists store the high-frequency streaming data points
  List<double> _ecgBuffer = [];
  List<double> _respBuffer = [];
  List<double> _tempBuffer = [];
  List<double> _accXBuffer = [];
  List<double> _accYBuffer = [];
  List<double> _accZBuffer = [];

  Timer? _oneMinuteTimer;
  bool isCollecting = false;

  SensorManager({required this.userId, this.samplingRate = 700});

  // START HDS COLLECTION
  void startCollection() {
    isCollecting = true;
    _clearBuffers();

    // This periodic timer fires exactly every 60 seconds
    _oneMinuteTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (_ecgBuffer.isEmpty || _respBuffer.isEmpty) {
        print('Buffer warning: No raw sensor data accumulated in the last minute.');
        return;
      }

      // Snapshot the current buffers so we can clear the main ones instantly
      // This prevents losing data points that arrive while the network call runs
      final ecgToSend = List<double>.from(_ecgBuffer);
      final respToSend = List<double>.from(_respBuffer);
      final tempToSend = List<double>.from(_tempBuffer);
      final accXToSend = List<double>.from(_accXBuffer);
      final accYToSend = List<double>.from(_accYBuffer);
      final accZToSend = List<double>.from(_accZBuffer);

      _clearBuffers();

      print('60 seconds up! Shipping ${ecgToSend.length} raw samples to Hugging Face...');
      
      // Send the raw data blocks over the internet bridge
      bool success = await ApiService.sendRawSensorData(
        userId: userId,
        samplingRate: samplingRate,
        ecg: ecgToSend,
        resp: respToSend,
        temp: tempToSend,
        accX: accXToSend,
        accY: accYToSend,
        accZ: accZToSend,
      );

      if (!success) {
        print('Failed to transmit this minute data block.');
      }
    });
  }

  // BLE STREAM RECEIVER
  // Your Bluetooth package listener will call these methods every single time 
  // the chest strap updates a data point over BLE!
  void onEcgDataReceived(double value) {
    if (isCollecting) _ecgBuffer.add(value);
  }

  void onRespDataReceived(double value) {
    if (isCollecting) _respBuffer.add(value);
  }

  void onTempDataReceived(double value) {
    if (isCollecting) _tempBuffer.add(value);
  }

  void onAccelerometerDataReceived(double x, double y, double z) {
    if (isCollecting) {
      _accXBuffer.add(x);
      _accYBuffer.add(y);
      _accZBuffer.add(z);
    }
  }

  // CLEAN UP
  void stopCollection() {
    isCollecting = false;
    _oneMinuteTimer?.cancel();
    _clearBuffers();
  }

  void _clearBuffers() {
    _ecgBuffer.clear();
    _respBuffer.clear();
    _tempBuffer.clear();
    _accXBuffer.clear();
    _accYBuffer.clear();
    _accZBuffer.clear();
  }
}