# Aura patient-issued QR invitations for ClinAnx

## Purpose
The existing **Connect to Doctor** screen keeps the static Aura Participant ID QR for identity-sharing only. It **does not** authorize a clinician to view the record. **Give clinician a code** now opens a separate invitation dialog that shows a QR alongside the **same** patient-authorized one-use code.

## End-to-end contract
1. Aura authenticates the patient on the central backend and requests `POST /v1/patients/me/assignment-invites` with its patient-scoped JWT.
2. The backend returns `invite_code` and `expires_at`. No patient identity or health data is embedded in the QR.
3. Aura encodes **the raw invitation token**, without modifying case, URL encoding, or adding a Participant ID.
4. The clinician selects **Patients → Link patient → Scan invitation QR** in ClinAnx (or manually enters the displayed code).
5. ClinAnx uses its existing authenticated `POST /v1/clinicians/me/assignments` redemption endpoint. The backend validates single-use, expiry, and clinician identity before creating the assignment.
6. ClinAnx refreshes its server-owned assigned roster. Aura does not assign clinicians locally.

**QR format:** the current backend uses `secrets.token_urlsafe(32)`, producing a 43-character base64url token. The ClinAnx scanner recognizes exactly this format or `clinanx://invite/<token>`. Aura emits the **raw token** for fewer parsing/versioning assumptions. If the backend ever returns another code shape, Aura continues to show the manual code but does not falsely claim it can be scanned.

## Expiry and privacy
- The source of truth is the backend expiry and redemption state. Aura also hides the displayed QR and code once the response's expiration time elapses.
- Invitations are bearer-style access grants for clinician assignment: share only with the intended healthcare professional.
- Do not share patient JWTs, installation secrets, Participant IDs, raw notes, or risk scores as the QR payload.
- Invites are not a login mechanism and do not change the central canonical `subject_id`.

## Testing
- `flutter test test/share_participant_id_page_test.dart test/clinician_invitation_dialog_test.dart test/patient_backend_contract_test.dart`
- `flutter analyze`
- Verify against the **same** HTTPS backend deployment on real Aura and ClinAnx devices.
- Ensure QR scan reads the exact token and manual entry works if scanning is unavailable.
- Confirm expired/used invitations are rejected by the backend, scanner never treats the original Participant ID QR as permission, and the server assignment roster refreshes.
- Camera permission is required **only on ClinAnx**; Aura is generating QR codes, not scanning them.

This feature does not introduce any new backend endpoints, authentication tokens, or model changes.
