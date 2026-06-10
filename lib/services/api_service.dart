import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Replace this with your actual Hugging Face Space URL
  static const String baseUrl = 'https://dewdu-physiological-anxiety-escalation.hf.space';

  // INGEST ENDPOINT: Sends high-frequency raw arrays directly to the server
  static Future<bool> sendRawSensorData({
    required String userId,
    required int samplingRate,
    required List<double> ecg,
    required List<double> resp,
    required List<double> temp,
    required List<double> accX,
    required List<double> accY,
    required List<double> accZ,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/ingest'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'sampling_rate': samplingRate,
          'ecg': ecg,
          'resp': resp,
          'temp': temp,
          'acc_x': accX,
          'acc_y': accY,
          'acc_z': accZ,
        }),
      );

      if (response.statusCode == 200) {
        print('Raw signal window processed by server and saved to InfluxDB!');
        return true;
      } else {
        print('Server data quality guard rejected the window: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Network exception during raw ingest: $e');
      return false;
    }
  }

  // CALIBRATION ENDPOINT: Caches per-user baseline stats for live Z-score scaling
  static Future<bool> setNormalizationParams({
    required String userId,
    required List<double> bMean,
    required List<double> bStd,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/set_norm_params/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'b_mean': bMean,
          'b_std': bStd,
        }),
      );

      if (response.statusCode == 200) {
        print('User calibration parameters successfully loaded into server memory.');
        return true;
      } else {
        print('Calibration failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Network exception during calibration: $e');
      return false;
    }
  }

  // PREDICT ENDPOINT: Requests the rolling 19-minute anomaly forecasting array
  static Future<Map<String, dynamic>> getEscalationForecast(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/predict/$userId'));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Prediction pipeline failed: ${response.body}');
        return {'status': 'error', 'message': 'API Inference Crash'};
      }
    } catch (e) {
      print('Network exception during prediction: $e');
      return {'status': 'error', 'message': 'Network offline'};
    }
  }
}