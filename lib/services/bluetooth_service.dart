import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  // UUIDs based on Hardware Team specs
  static const String NUS_SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String NUS_TX_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

  // Callback to pass parsed data to the SensorManager
  Function(double ecg, double accX, double accY, double accZ, double temp)? onDataReceived;

  bool get isConnected => _connectedDevice != null;

  Future<void> startScan() async {
    // Check if bluetooth is on
    if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on) {
      // Start scanning for devices advertising the NUS Service
      await FlutterBluePlus.startScan(
        withServices: [Guid(NUS_SERVICE_UUID)],
        timeout: const Duration(seconds: 15),
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.advName.contains("Chest Strap V3") || r.device.advName.isNotEmpty) {
            _connectToDevice(r.device);
            break;
          }
        }
      });
    } else {
      debugPrint("Bluetooth is off");
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();

      await device.connect(autoConnect: false);
      _connectedDevice = device;
      debugPrint("Connected to ${device.advName}");

      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toUpperCase() == NUS_SERVICE_UUID.toUpperCase()) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() == NUS_TX_UUID.toUpperCase()) {
              await characteristic.setNotifyValue(true);
              
              // Handle incoming data
              _notifySubscription = characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  _parseCSV(value);
                }
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error connecting to device: $e");
    }
  }

  void _parseCSV(List<int> bytes) {
    try {
      // Convert bytes to UTF-8 string
      final csvString = utf8.decode(bytes).trim();
      final parts = csvString.split(',');
      
      // Expected: Timestamp, ECG_CH1, ECG_CH2, Accel_X, Accel_Y, Accel_Z, Gyro_X, Gyro_Y, Gyro_Z, Body_Temperature
      if (parts.length >= 10) {
        final double ecgCh1 = double.tryParse(parts[1]) ?? 0.0;
        final double accX = double.tryParse(parts[3]) ?? 0.0;
        final double accY = double.tryParse(parts[4]) ?? 0.0;
        final double accZ = double.tryParse(parts[5]) ?? 0.0;
        final double temp = double.tryParse(parts[9]) ?? 0.0;

        // Send to Sensor Manager
        if (onDataReceived != null) {
          onDataReceived!(ecgCh1, accX, accY, accZ, temp);
        }
      }
    } catch (e) {
      debugPrint("Error parsing BLE data: $e");
    }
  }

  Future<void> disconnect() async {
    _notifySubscription?.cancel();
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
  }
}
