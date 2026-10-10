import 'package:anxiety_mobile_app/services/api_service.dart';
import 'package:anxiety_mobile_app/widgets/clinician_invitation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  // Exactly the length/character class of a backend token_urlsafe(32) invite.
  const invitationCode = 'A1234567890123456789012345678901234567890_Z';

  Future<void> openInvitation(WidgetTester tester, AssignmentInvite invite) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ClinicianInvitationDialog(invite: invite),
              ),
              child: const Text('Open invitation'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open invitation'));
    await tester.pumpAndSettle();
  }

  testWidgets('QR and manual code use the exact same case-sensitive token', (tester) async {
    expect(invitationCode.length, 43);
    await openInvitation(
      tester,
      AssignmentInvite(
        invitationCode,
        DateTime.now().toUtc().add(const Duration(minutes: 10)),
      ),
    );
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.data, invitationCode);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText && widget.data == invitationCode,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Expires at'), findsOneWidget);
    expect(find.textContaining('Share it only'), findsOneWidget);
  });

  testWidgets('copy action copies the same invite token, not a participant ID', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await openInvitation(
      tester,
      AssignmentInvite(
        invitationCode,
        DateTime.now().toUtc().add(const Duration(minutes: 10)),
      ),
    );
    await tester.tap(find.text('Copy code'));
    await tester.pump();
    expect(copied, invitationCode);
  });

  testWidgets('already expired invitations never display QR or code', (tester) async {
    await openInvitation(
      tester,
      AssignmentInvite(
        invitationCode,
        DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      ),
    );
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('has expired'), findsOneWidget);
    expect(find.text('Copy code'), findsNothing);
    expect(find.text(invitationCode), findsNothing);
  });

  testWidgets('open invitation hides QR after the backend expiry', (tester) async {
    await openInvitation(
      tester,
      AssignmentInvite(
        invitationCode,
        DateTime.now().toUtc().add(const Duration(seconds: 5)),
      ),
    );
    expect(find.byType(QrImageView), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('has expired'), findsOneWidget);
  });

  testWidgets('older non-QR invitation formats retain a manual fallback', (tester) async {
    await openInvitation(
      tester,
      AssignmentInvite(
        'legacy-invite',
        DateTime.now().toUtc().add(const Duration(minutes: 10)),
      ),
    );
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('QR scanning is unavailable'), findsOneWidget);
    expect(find.text('legacy-invite'), findsOneWidget);
    expect(find.text('Copy code'), findsOneWidget);
  });
}
