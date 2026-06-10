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

    // Toggle this to true to auto-generate perfect raw waveforms without the chest strap
    bool useSimulationMode = true;

    // This periodic timer fires exactly every 60 seconds
    _oneMinuteTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      
      // --- CHEAT MODE: SYNTHETIC WAVEFORM GENERATOR ---
      if (useSimulationMode) {
        print('Cheat Mode Active: Generating 60 seconds of raw physiological waveforms...');
        _clearBuffers();
        
        // 60 seconds of data at 700 samples per second = 42,000 data points
        int totalSamples = 60 * samplingRate;
        
        for (int i = 0; i < totalSamples; i++) {
          // 1. Synthetic ECG: Creates a sharp electrical heartbeat spike every 600 samples (~70 BPM)
          if (i % 600 == 0) {
            _ecgBuffer.add(1.5); // The sharp R-peak
          } else if (i % 600 == 10) {
            _ecgBuffer.add(-0.3); // The S-wave drop
          } else {
            // Micro-vibrations so the signal isn't completely flat
            _ecgBuffer.add(0.02 * (i % 10 == 0 ? 1.0 : -1.0)); 
          }

          // 2. Synthetic Respiration: A simple wave mimicking 16 breaths per minute
          _respBuffer.add(0.5 * (i % 2625 < 1312 ? 1.0 : -1.0));

          // 3. Synthetic Temperature: A steady, normal 36.6 degrees Celsius
          _tempBuffer.add(36.6);

          // 4. Synthetic Accelerometer: Normal stationary numbers (gravity pulling on Z-axis)
          _accXBuffer.add(0.02);
          _accYBuffer.add(0.02);
          _accZBuffer.add(0.98); 
        }
      }

      // Main safety guard clause: Don't transmit if buffers are empty
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
      
      // Send the raw data blocks over the internet bridge using correct camelCase parameter names
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