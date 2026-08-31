import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returning participants refresh their central subject id at startup', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('Future<void> _syncCentralSubjectId(String userId)'));
    expect(source, contains('ApiService.selfEnrol(userId)'));
    expect(
      source,
      contains('ParticipantIdentityService.saveCentralSubjectId(subjectId)'),
    );
    expect(source, contains('await _syncCentralSubjectId(userId);'));
  });
}
