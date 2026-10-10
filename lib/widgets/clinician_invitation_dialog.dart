import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_service.dart';

/// Displays a patient-authorized, short-lived clinician assignment invitation.
///
/// The exact same backend-issued token is shown as a QR payload and a manual
/// code. It is never a Participant ID, central subject ID, or patient JWT.
/// ClinAnx still validates the one-use token on the central backend.
class ClinicianInvitationDialog extends StatefulWidget {
  const ClinicianInvitationDialog({
    super.key,
    required this.invite,
  });

  final AssignmentInvite invite;

  @override
  State<ClinicianInvitationDialog> createState() =>
      _ClinicianInvitationDialogState();
}

class _ClinicianInvitationDialogState extends State<ClinicianInvitationDialog> {
  // Must match ClinAnx invitation QR parsing and the backend's
  // secrets.token_urlsafe(32) contract (43 case-sensitive base64url chars).
  static final RegExp _qrTokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
  Timer? _expiryTimer;
  late bool _expired;

  @override
  void initState() {
    super.initState();
    final remaining =
        widget.invite.expiresAt.toUtc().difference(DateTime.now().toUtc());
    _expired = remaining <= Duration.zero;
    if (!_expired) {
      _expiryTimer = Timer(remaining, () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyInvitation() async {
    if (_expired) return;
    await Clipboard.setData(ClipboardData(text: widget.invite.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invitation code copied. Share only with your clinician.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qrSupported = _qrTokenPattern.hasMatch(widget.invite.code);
    final expiryText = DateFormat('d MMM yyyy, h:mm a')
        .format(widget.invite.expiresAt.toLocal());

    return AlertDialog(
      title: const Text('Clinician invitation'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ask your clinician to open Link patient in ClinAnx. '
              'They can scan this invitation QR or enter the code below.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_expired) ...[
              const Icon(Icons.timer_off_outlined, size: 44),
              const SizedBox(height: 8),
              const Text(
                'This invitation has expired. Close this window and generate a new one.',
                textAlign: TextAlign.center,
              ),
            ] else ...[
              if (qrSupported)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: widget.invite.code,
                    version: QrVersions.auto,
                    size: 208,
                    backgroundColor: Colors.white,
                    semanticsLabel: 'One-use clinician invitation QR code',
                  ),
                )
              else
                const Text(
                  'QR scanning is unavailable for this invitation format. '
                  'Your clinician can enter the code manually.',
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 14),
              const Text(
                'One-use invitation code',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              SelectableText(
                widget.invite.code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Expires at $expiryText (local time)',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Text(
                'This invitation grants access to a clinician who redeems it. '
                'Share it only with the healthcare professional you choose.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_expired)
          TextButton.icon(
            onPressed: _copyInvitation,
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy code'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
