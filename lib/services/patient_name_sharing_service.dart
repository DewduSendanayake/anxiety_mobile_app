import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'participant_identity_service.dart';
import 'patient_session_service.dart';

/// Opt-in state reflects a confirmed server write, not just local intent.
class PatientNameSharingService {
  static const consentKey = 'clinician_display_name_shared';

  // Consent belongs to a specific pseudonymous participant, not to the phone.
  // A second Aura account must never inherit the prior account's sharing opt-in.
  static String _keyFor(String participantId) => '$consentKey:$participantId';

  static Future<bool> isShared(String participantId) async {
    if (!ParticipantIdentityService.isParticipantId(participantId)) return false;
    return (await SharedPreferences.getInstance()).getBool(_keyFor(participantId)) ?? false;
  }

  static Future<String?> _subjectFor(String participantId) async {
    if (!ParticipantIdentityService.isParticipantId(participantId)) return null;
    final expected = await ParticipantIdentityService.getCentralSubjectId();
    final active = await PatientSessionService.instance.currentSession();
    if (active != null && expected != null && active.subjectId == expected) {
      return active.subjectId;
    }
    final result = await ApiService.selfEnrol(
      participantId,
      expectedSubjectId: expected,
    );
    if (result == null) return null;
    await ParticipantIdentityService.saveCentralSubjectId(result);
    return result;
  }

  static Future<bool> share(String participantId) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(ParticipantIdentityService.displayNameKey)?.trim() ?? '';
    if (name.isEmpty || name.length > 80) return false;
    final subject = await _subjectFor(participantId);
    if (subject == null) return false;
    final success = await ApiService.updateClinicianDisplayName(
      displayName: name,
      expectedSubjectId: subject,
      participantId: participantId,
    );
    if (success) await prefs.setBool(_keyFor(participantId), true);
    return success;
  }

  static Future<bool> syncIfShared(String participantId) async {
    if (!await isShared(participantId)) return true;
    return share(participantId);
  }

  static Future<bool> revoke(String participantId) async {
    final subject = await _subjectFor(participantId);
    if (subject == null) return false;
    final success = await ApiService.revokeClinicianDisplayName(
      expectedSubjectId: subject,
      participantId: participantId,
    );
    if (success) {
      await (await SharedPreferences.getInstance()).setBool(_keyFor(participantId), false);
    }
    return success;
  }
}
