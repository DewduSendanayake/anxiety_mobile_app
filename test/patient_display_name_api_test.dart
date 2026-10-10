import 'dart:convert';

import 'package:anxiety_mobile_app/services/api_service.dart';
import 'package:anxiety_mobile_app/services/patient_session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore implements PatientSecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PatientSessionService> authenticated() async {
    final service = PatientSessionService(store: _MemoryStore());
    await service.saveSession(
      subjectId: 'subject-a',
      accessToken: 'patient-test-jwt',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    return service;
  }

  test('patient JWT securely updates only own display name', () async {
    final session = await authenticated();
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/v1/patients/me/display-name');
      expect(request.headers['Authorization'], 'Bearer patient-test-jwt');
      expect(jsonDecode(request.body), {'display_name': 'Patient Example'});
      expect(request.body, isNot(contains('subject-a')));
      return http.Response(jsonEncode({'shared': true}), 200);
    });
    expect(await ApiService.updateClinicianDisplayName(
      displayName: 'Patient Example',
      expectedSubjectId: 'subject-a',
      client: client,
      sessionService: session,
      backendBase: 'https://backend.example',
    ), isTrue);
  });

  test('revocation uses patient JWT, never query string or subject id', () async {
    final session = await authenticated();
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/v1/patients/me/display-name');
      expect(request.url.query, isEmpty);
      expect(request.headers['Authorization'], 'Bearer patient-test-jwt');
      return http.Response(jsonEncode({'shared': false}), 200);
    });
    expect(await ApiService.revokeClinicianDisplayName(
      expectedSubjectId: 'subject-a',
      client: client,
      sessionService: session,
      backendBase: 'https://backend.example',
    ), isTrue);
  });

  test('server refusal does not report a successful share', () async {
    final session = await authenticated();
    final client = MockClient((request) async => http.Response('{}', 503));
    expect(await ApiService.updateClinicianDisplayName(
      displayName: 'Patient Example',
      expectedSubjectId: 'subject-a',
      client: client,
      sessionService: session,
      backendBase: 'https://backend.example',
    ), isFalse);
  });
}
