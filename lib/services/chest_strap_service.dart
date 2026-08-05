import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChestStrapState { disabled, scanning, connecting, connected, disconnected }

class ChestStrapReading {
  final int timestamp;
  final double meanHR;
  final double meanRR;
  final double sdnn;
  final double rmssd;
  final double meanBR;
  final double stdBR;
  final double meanTemp;
  final double stdTemp;
  final double meanAccMag;
  final double stdAccMag;

  const ChestStrapReading({
    required this.timestamp,
    required this.meanHR,
    required this.meanRR,
    required this.sdnn,
    required this.rmssd,
    required this.meanBR,
    required this.stdBR,
    required this.meanTemp,
    required this.stdTemp,
    required this.meanAccMag,
    required this.stdAccMag,
  });

  factory ChestStrapReading.fromCsv(String csvLine) {
    final parts = csvLine.split(',');
    if (parts.length != 11) {
      throw FormatException('Invalid CSV length');
    }
    return ChestStrapReading(
      timestamp: int.parse(parts[0]),
      meanHR: double.parse(parts[1]),
      meanRR: double.parse(parts[2]),
      sdnn: double.parse(parts[3]),
      rmssd: double.parse(parts[4]),
      meanBR: double.parse(parts[5]),
      stdBR: double.parse(parts[6]),
      meanTemp: double.parse(parts[7]),
      stdTemp: double.parse(parts[8]),
      meanAccMag: double.parse(parts[9]),
      stdAccMag: double.parse(parts[10]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'meanHR': meanHR,
      'meanRR': meanRR,
      'sdnn': sdnn,
      'rmssd': rmssd,
      'meanBR': meanBR,
      'stdBR': stdBR,
      'meanTemp': meanTemp,
      'stdTemp': stdTemp,
      'meanAccMag': meanAccMag,
      'stdAccMag': stdAccMag,
    };
  }

  factory ChestStrapReading.fromJson(Map<String, dynamic> json) {
    return ChestStrapReading(
      timestamp: json['timestamp'] as int,
      meanHR: (json['meanHR'] as num).toDouble(),
      meanRR: (json['meanRR'] as num).toDouble(),
      sdnn: (json['sdnn'] as num).toDouble(),
      rmssd: (json['rmssd'] as num).toDouble(),
      meanBR: (json['meanBR'] as num).toDouble(),
      stdBR: (json['stdBR'] as num).toDouble(),
      meanTemp: (json['meanTemp'] as num).toDouble(),
      stdTemp: (json['stdTemp'] as num).toDouble(),
      meanAccMag: (json['meanAccMag'] as num).toDouble(),
      stdAccMag: (json['stdAccMag'] as num).toDouble(),
    );
  }

  double get riskScore {
    double hrScore = 0.0;
    if (meanHR > 110) {
      hrScore = 100.0;
    } else if (meanHR > 90) {
      hrScore = 40.0 + (meanHR - 90) / (110 - 90) * (80 - 40);
    } else if (meanHR > 70) {
      hrScore = (meanHR - 70) / (90 - 70) * 40.0;
    }

    double brScore = 0.0;
    if (meanBR > 26) {
      brScore = 100.0;
    } else if (meanBR > 20) {
      brScore = 40.0 + (meanBR - 20) / (26 - 20) * (80 - 40);
    } else if (meanBR > 16) {
      brScore = (meanBR - 16) / (20 - 16) * 40.0;
    }

    double tempScore = 0.0;
    double tempDeviation = (meanTemp - 36.75).abs();
    if (tempDeviation > 0.6) {
      tempScore = 100.0;
    } else if (tempDeviation > 0.3) {
      tempScore = (tempDeviation - 0.3) / (0.6 - 0.3) * 50.0 + 50.0;
    }

    double hrvScore = 0.0;
    if (rmssd >= 40) {
      hrvScore = 0.0;
    } else if (rmssd >= 20) {
      hrvScore = (40.0 - rmssd) / 20.0 * 50.0;
    } else {
      hrvScore = 50.0 + (20.0 - rmssd) / 20.0 * 50.0;
      if (hrvScore > 100.0) hrvScore = 100.0;
    }

    double total = (hrScore * 0.35) + (brScore * 0.25) + (tempScore * 0.15) + (hrvScore * 0.25);
    return total.clamp(0.0, 100.0);
  }

  String get riskLabel {
    final score = riskScore;
    if (score <= 20) return 'Low';
    if (score <= 45) return 'Moderate';
    if (score <= 70) return 'Elevated';
    return 'High';
  }

  String get hrStatus {
    if (meanHR <= 60) return 'Low';
    if (meanHR <= 90) return 'Normal';
    if (meanHR <= 110) return 'Elevated';
    return 'High';
  }

  String get brStatus {
    if (meanBR <= 12) return 'Low';
    if (meanBR <= 20) return 'Normal';
    if (meanBR <= 26) return 'Elevated';
    return 'High';
  }

  String get tempStatus {
    if (meanTemp < 36.1) return 'Low';
    if (meanTemp <= 37.2) return 'Normal';
    if (meanTemp <= 37.8) return 'Elevated';
    return 'High';
  }

  String get hrvStatus {
    if (rmssd >= 40) return 'Calm';
    if (rmssd >= 25) return 'Normal';
    if (rmssd >= 15) return 'Stressed';
    return 'High Stress';
  }
}

class ChestStrapService {
  static final ChestStrapService _instance = ChestStrapService._internal();

  factory ChestStrapService() => _instance;

  final ValueNotifier<ChestStrapState> connectionState = ValueNotifier(ChestStrapState.disconnected);
  Function(ChestStrapReading)? onDataReceived;
  ChestStrapReading? lastReading;

  BluetoothDevice? _connectedDevice;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _txSubscription;
  String _receiveBuffer = '';
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  
  static const String _nusServiceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String _nusTxUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String _prefKey = 'chest_strap_last_reading';

  ChestStrapService._internal() {
    _loadPersistedReading();
  }

  Future<void> _loadPersistedReading() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKey);
      if (jsonStr != null) {
        lastReading = ChestStrapReading.fromJson(jsonDecode(jsonStr));
      }
    } catch (e) {
      debugPrint('Error loading persisted reading: $e');
    }
  }

  Future<void> _saveReading(ChestStrapReading reading) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(reading.toJson()));
    } catch (e) {
      debugPrint('Error saving reading: $e');
    }
  }

  bool get isConnected => connectionState.value == ChestStrapState.connected;

  Future<void> startScan() async {
    try {
      debugPrint('[ChestStrap] Checking Bluetooth adapter state...');
      if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.off) {
        debugPrint('[ChestStrap] Bluetooth adapter is OFF');
        connectionState.value = ChestStrapState.disabled;
        return;
      }

      connectionState.value = ChestStrapState.scanning;
      debugPrint('[ChestStrap] Scanning for ChestStrap_V3...');

      // Listen for scan results BEFORE starting scan to avoid race condition
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        (results) async {
          try {
            ScanResult? targetResult;
            for (var result in results) {
              debugPrint('[ChestStrap] Found device: ${result.device.advName} (${result.device.remoteId})');
              if (result.device.advName.contains('ChestStrap_V3')) {
                targetResult = result;
                break;
              }
            }

            if (targetResult != null) {
              debugPrint('[ChestStrap] Target device found! Stopping scan...');
              await FlutterBluePlus.stopScan();
              await connectToDevice(targetResult.device);
            }
          } catch (e) {
            debugPrint('[ChestStrap] Error processing scan results: $e');
          }
        },
        onError: (e) {
          debugPrint('[ChestStrap] Scan error: $e');
          connectionState.value = ChestStrapState.disconnected;
        },
      );

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint('[ChestStrap] Error starting scan: $e');
      connectionState.value = ChestStrapState.disconnected;
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      connectionState.value = ChestStrapState.connecting;
      _connectedDevice = device;
      _receiveBuffer = ''; // Clear stale buffer from previous connection
      
      debugPrint('[ChestStrap] Connecting to ${device.advName} (${device.remoteId})...');
      await _connectedDevice!.connect(
        timeout: const Duration(seconds: 10),
      );
      
      _reconnectAttempts = 0;
      debugPrint('[ChestStrap] Connected! Requesting MTU 256...');

      // Request larger MTU so the ~90-byte CSV arrives in 1-2 packets
      // instead of 4-5 with the default 23-byte MTU.
      final mtu = await _connectedDevice!.requestMtu(256);
      debugPrint('[ChestStrap] MTU negotiated: $mtu');
      
      _connectionSubscription?.cancel();
      _connectionSubscription = _connectedDevice!.connectionState.listen(_onConnectionStateChanged);

      connectionState.value = ChestStrapState.connected;

      debugPrint('[ChestStrap] Discovering services...');
      final services = await _connectedDevice!.discoverServices();
      debugPrint('[ChestStrap] Found ${services.length} services');

      BluetoothService? nusService;
      for (var s in services) {
        if (s.uuid.toString().toUpperCase() == _nusServiceUuid.toUpperCase()) {
          nusService = s;
          break;
        }
      }

      if (nusService != null) {
        debugPrint('[ChestStrap] NUS service found. Looking for TX characteristic...');
        BluetoothCharacteristic? txChar;
        for (var c in nusService.characteristics) {
          if (c.uuid.toString().toUpperCase() == _nusTxUuid.toUpperCase()) {
            txChar = c;
            break;
          }
        }

        if (txChar != null) {
          debugPrint('[ChestStrap] TX characteristic found. Subscribing to notifications...');
          await txChar.setNotifyValue(true);
          _txSubscription?.cancel();
          _txSubscription = txChar.lastValueStream.listen((value) {
            if (value.isNotEmpty) {
              final str = utf8.decode(value);
              _receiveBuffer += str;
              _processBuffer();
            }
          });
          debugPrint('[ChestStrap] ✅ Fully connected and listening for data.');
        } else {
          debugPrint('[ChestStrap] ⚠️ TX characteristic NOT found in NUS service!');
        }
      } else {
        debugPrint('[ChestStrap] ⚠️ NUS service NOT found! Available services:');
        for (var s in services) {
          debugPrint('[ChestStrap]   - ${s.uuid}');
        }
      }
    } catch (e) {
      debugPrint('[ChestStrap] Error connecting to device: $e');
      connectionState.value = ChestStrapState.disconnected;
    }
  }
  
  void _processBuffer() {
    // Primary path: newline-delimited parsing (firmware sends \n)
    int newlineIndex = _receiveBuffer.indexOf('\n');
    while (newlineIndex != -1) {
      String line = _receiveBuffer.substring(0, newlineIndex).trim();
      _receiveBuffer = _receiveBuffer.substring(newlineIndex + 1);
      
      if (line.isNotEmpty) {
        _parseCsvLine(line);
      }
      
      newlineIndex = _receiveBuffer.indexOf('\n');
    }

    // Fallback: if no newline found but buffer has a complete 11-field CSV
    // (10 commas), extract and parse it. Guards against firmware versions
    // that don't append \n.
    if (_receiveBuffer.isNotEmpty && !_receiveBuffer.contains('\n')) {
      final commaCount = ','.allMatches(_receiveBuffer).length;
      if (commaCount >= 10) {
        // Find the end of the first complete 11-field CSV line
        int count = 0;
        int endIndex = -1;
        for (int i = 0; i < _receiveBuffer.length; i++) {
          if (_receiveBuffer[i] == ',') count++;
          if (count == 10) {
            // Find the end of the 11th field (next comma or end of string)
            int fieldEnd = _receiveBuffer.indexOf(',', i + 1);
            endIndex = fieldEnd == -1 ? _receiveBuffer.length : fieldEnd;
            break;
          }
        }
        if (endIndex != -1) {
          String line = _receiveBuffer.substring(0, endIndex).trim();
          _receiveBuffer = _receiveBuffer.substring(endIndex).trimLeft();
          if (line.isNotEmpty) {
            debugPrint('[ChestStrap] Fallback parser extracted line (no newline in buffer)');
            _parseCsvLine(line);
          }
        }
      }
    }

    // Safety: prevent unbounded buffer growth from corrupt data
    if (_receiveBuffer.length > 1024) {
      debugPrint('[ChestStrap] ⚠️ Receive buffer overflow (${_receiveBuffer.length} bytes). Clearing.');
      _receiveBuffer = '';
    }
  }

  void _parseCsvLine(String line) {
    try {
      final reading = ChestStrapReading.fromCsv(line);
      lastReading = reading;
      _saveReading(reading);
      debugPrint('[ChestStrap] 📊 HR=${reading.meanHR.toStringAsFixed(1)} BR=${reading.meanBR.toStringAsFixed(1)} Temp=${reading.meanTemp.toStringAsFixed(1)} RMSSD=${reading.rmssd.toStringAsFixed(1)}');
      if (onDataReceived != null) {
        onDataReceived!(reading);
      }
    } catch (e) {
      debugPrint('[ChestStrap] Error parsing CSV "$line": $e');
    }
  }

  void _onConnectionStateChanged(BluetoothConnectionState state) {
    debugPrint('[ChestStrap] Connection state changed: $state');
    if (state == BluetoothConnectionState.disconnected) {
      connectionState.value = ChestStrapState.disconnected;
      _txSubscription?.cancel();
      _connectionSubscription?.cancel();
      
      if (_reconnectAttempts < _maxReconnectAttempts && _connectedDevice != null) {
        _reconnectAttempts++;
        debugPrint('[ChestStrap] Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in 3s...');
        Future.delayed(const Duration(seconds: 3), () {
          if (_connectedDevice != null) {
            connectToDevice(_connectedDevice!);
          }
        });
      } else if (_reconnectAttempts >= _maxReconnectAttempts) {
        debugPrint('[ChestStrap] ⚠️ Max reconnect attempts reached. Giving up.');
      }
    }
  }

  Future<void> disconnect() async {
    try {
      _scanSubscription?.cancel();
      _connectionSubscription?.cancel();
      _txSubscription?.cancel();
      
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
      }
      connectionState.value = ChestStrapState.disconnected;
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }
}
