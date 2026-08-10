import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'login_page.dart';

/// InformedConsentPage
///
/// Used in TWO modes controlled by [readOnly]:
///
///   readOnly = false  (default)
///   ── First-run consent flow.
///      Patient must scroll to bottom AND tick all 6 boxes.
///      "I Consent & Continue" button unlocks only when both are done.
///      On confirmation, all state is persisted to SharedPreferences.
///
///   readOnly = true
///   ── Called from Profile / "Manage Data Rights" section.
///      All content is shown.  All checkboxes are ticked and LOCKED
///      (non-interactive) reflecting the consent already given.
///      The consent timestamp is shown at the bottom.
///      No "Consent" button is shown — a "Close" button replaces it.
///
/// The constructor parameter allows any page to open this in read-only mode:
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => const InformedConsentPage(readOnly: true),
///   ));
class InformedConsentPage extends StatefulWidget {
  final bool readOnly;
  const InformedConsentPage({super.key, this.readOnly = false});

  @override
  State<InformedConsentPage> createState() => _InformedConsentPageState();
}

class _InformedConsentPageState extends State<InformedConsentPage> {
  final ScrollController _scrollController = ScrollController();

  bool _hasScrolledToBottom = false;
  String _consentTimestamp = '';

  // Seven declarations — loaded from prefs in readOnly mode.
  bool _cbAge       = false;
  bool _cbPurpose   = false;
  bool _cbData      = false;
  bool _cbPhysio    = false;
  bool _cbStorage   = false;
  bool _cbRights    = false;
  bool _cbVoluntary = false;
  bool _cbLiability = false;

  bool get _allChecked =>
      _cbAge && _cbPurpose && _cbData && _cbPhysio && _cbStorage && _cbRights && _cbVoluntary && _cbLiability;

  bool get _canProceed => _hasScrolledToBottom && _allChecked;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(() {
      if (!_hasScrolledToBottom &&
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 60) {
        setState(() => _hasScrolledToBottom = true);
      }
    });

    if (widget.readOnly) {
      _loadPersistedConsent();
    }
  }

  /// In readOnly mode, populate all fields from the persisted consent record.
  Future<void> _loadPersistedConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final String? ts = prefs.getString('consent_timestamp');
    if (!mounted) return;
    setState(() {
      _cbAge       = prefs.getBool('consent_cb_age')       ?? true;
      _cbPurpose   = prefs.getBool('consent_cb_purpose')   ?? true;
      _cbData      = prefs.getBool('consent_cb_data')      ?? true;
      _cbPhysio    = prefs.getBool('consent_cb_physio')    ?? true;
      _cbStorage   = prefs.getBool('consent_cb_storage')   ?? true;
      _cbRights    = prefs.getBool('consent_cb_rights')    ?? true;
      _cbVoluntary = prefs.getBool('consent_cb_voluntary') ?? true;
      _cbLiability = prefs.getBool('consent_cb_liability') ?? true;
      if (ts != null) {
        try {
          final dt = DateTime.parse(ts).toLocal();
          _consentTimestamp =
              DateFormat('dd MMM yyyy  HH:mm').format(dt);
        } catch (_) {
          _consentTimestamp = ts;
        }
      }
      // In read-only mode we always show the page as fully scrolled so the
      // timestamp footer is visible immediately.
      _hasScrolledToBottom = true;
    });
  }

  Future<void> _acceptConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final String ts = DateTime.now().toIso8601String();
    await prefs.setBool('consent_accepted',    true);
    await prefs.setString('consent_timestamp', ts);
    await prefs.setBool('consent_cb_age',       _cbAge);
    await prefs.setBool('consent_cb_purpose',   _cbPurpose);
    await prefs.setBool('consent_cb_data',      _cbData);
    await prefs.setBool('consent_cb_physio',    _cbPhysio);
    await prefs.setBool('consent_cb_storage',   _cbStorage);
    await prefs.setBool('consent_cb_rights',    _cbRights);
    await prefs.setBool('consent_cb_voluntary', _cbVoluntary);
    await prefs.setBool('consent_cb_liability', _cbLiability);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.kBgTop, AppTheme.kBgBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _institutionBadge(),
                          const SizedBox(height: 18),

                          // readOnly banner
                          if (widget.readOnly) _readOnlyBanner(),

                          // ── Section 1 ─────────────────────────────────
                          _sectionTitle("1. Why This Study Is Being Done"),
                          _paragraph(
                            "You are invited to join an approved research study run by the "
                            "Sri Lanka Institute of Information Technology (SLIIT). Joining is your choice. "
                            "Please read this form carefully before deciding.",
                          ),
                          _paragraph(
                            "This study looks at whether information collected by a phone in the background can "
                            "help show changes in anxiety among young adults over 12 months. This includes movement, "
                            "screen time, call and message totals, and answers about mood.",
                          ),
                          _divider(),

                          // ── Section 2 ─────────────────────────────────
                          _sectionTitle("2. How Long It Lasts and What You Do"),
                          _bulletItem("The study lasts 12 months from the day you join."),
                          _bulletItem("You keep this application installed and running on your Android device throughout the study."),
                          _bulletItem("Three short mood check-ins each day, in the morning, afternoon, and evening. Each takes about 1 to 2 minutes."),
                          _bulletItem("A 7-question anxiety check, called GAD-7, sent every week. It takes about 2 minutes."),
                          _bulletItem("A 10-question stress check, called PSS-10, sent every week. It takes about 3 minutes."),
                          _bulletItem("One set of questions about you, such as your age, education, and living situation, when you join."),
                          _divider(),

                          // ── Section 3 ─────────────────────────────────
                          _sectionTitle("3. What Data Will Be Collected?"),
                          _paragraph(
                            "The table below lists every type of data collected. This includes "
                            "phone activity, such as movement and screen use, and body readings "
                            "from a wearable chest strap, such as heart rate, breathing rate, body "
                            "temperature, and motion). The application does NOT read the content "
                            "of any SMS or phone call.",
                          ),
                          _dataTable(),
                          _divider(),

                          // ── Section 4 ─────────────────────────────────
                          _sectionTitle("4. How Your Data Is Protected and Stored Outside Sri Lanka"),
                          _paragraph(
                            "All data is sent through a protected internet connection and stored in Google Cloud, "
                            "which is run by Google LLC. The storage systems are outside Sri Lanka.",
                          ),
                          _paragraph(
                            "This transfer uses the rule for scientific research in Section 24 of "
                            "Sri Lanka's PDPA No. 9 of 2022.",
                          ),
                          _bulletItem("Your real name and phone number are NEVER stored with the research data."),
                          _bulletItem("All records are linked only to a randomly assigned Participant ID."),
                          _bulletItem("Saved locations are made less exact by about 1 km."),
                          _bulletItem("App names are grouped into general categories before they are saved."),
                          _bulletItem("Access is restricted to the named research team at SLIIT."),
                          _bulletItem("Data will be kept for no more than 5 years after the study ends, then permanently deleted."),
                          _divider(),

                          // ── Section 5 ─────────────────────────────────
                          _sectionTitle("5. Your Rights Over Your Data (PDPA No. 9 of 2022)"),
                          _paragraph("You have the following rights at any time:"),
                          _rightItem(Icons.visibility_outlined,  "See Your Data",       "Ask for a full copy of all data collected about you."),
                          _rightItem(Icons.edit_outlined,         "Correct Your Data",   "Ask us to correct personal data that is wrong."),
                          _rightItem(Icons.delete_outline,        "Delete Your Data",    "Ask us to delete all of your data at any time without penalty."),
                          _rightItem(Icons.pause_circle_outline,  "Limit Data Use",      "Ask us to pause the use of your data while a complaint is being handled."),
                          _rightItem(Icons.exit_to_app_outlined,  "Leave the Study",     "Leave the study at any time without any negative consequences."),
                          _paragraph(
                            "To exercise any right: email it22130648@my.sliit.lk with your Participant ID.",
                          ),
                          _divider(),

                          // ── Section 6 ─────────────────────────────────
                          _sectionTitle("6. Possible Risks and Benefits"),
                          _subTitle("Possible risks"),
                          _bulletItem("The risk is expected to be low. The app runs quietly in the background."),
                          _bulletItem("The app may use a little more battery, estimated at less than 5% per day."),
                          _bulletItem("Some questions about mood or anxiety may feel upsetting. You do not have to answer any question that makes you uncomfortable."),
                          _subTitle("Possible benefits"),
                          _bulletItem("You help research how phones may support mental health in South Asia."),
                          _bulletItem("The findings may help create future anxiety checks that are carefully tested for health care use."),
                          _bulletItem("You will not receive payment for joining."),
                          _divider(),

                          // ── Section 7 ─────────────────────────────────
                          _sectionTitle("7. Joining Is Your Choice and You Can Leave"),
                          _paragraph(
                            "Joining is your choice. You may leave at any time without giving a reason and without "
                            "any negative consequences. To leave, uninstall the app and email the research team if "
                            "you also want your earlier data deleted.",
                          ),
                          _divider(),

                          // ── Section 8 ─────────────────────────────────
                          _sectionTitle("8. Study Approval"),
                          _paragraph(
                            "This study is designed in accordance with the Declaration of Helsinki (2013), "
                            "ICH Good Clinical Practice guidelines, and Sri Lanka PDPA No. 9 of 2022. "
                            "Ethics Ref: SLIIT/IT/RES/2024  |  Study ID: ANXIETY-DIGITAL-2024",
                          ),
                          _divider(),

                          // ── Section 9 — Declarations ──────────────────
                          _sectionTitle("9. Your Agreement"),
                          _paragraph(
                            widget.readOnly
                                ? "The following statements were confirmed when you agreed to join. "
                                  "They are permanently locked and cannot be changed."
                                : "Please read each statement carefully and tick the box. "
                                  "All statements are required before you can continue.",
                          ),
                          const SizedBox(height: 6),

                          _consentCheck(
                            value: _cbAge,
                            key: 'age',
                            label: "I confirm that I am 18 years of age or older and allowed by law to agree to join this study.",
                          ),
                          _consentCheck(
                            value: _cbPurpose,
                            key: 'purpose',
                            label: "I understand why this study is being done, what I need to do, and that it lasts 12 months (Sections 1 & 2).",
                          ),
                          _consentCheck(
                            value: _cbData,
                            key: 'data',
                            label: "I understand what data is collected from my phone, including location, movement, call and message totals, and my check-in answers, and I consent to this collection (Section 3).",
                          ),
                          _consentCheck(
                            value: _cbPhysio,
                            key: 'physio',
                            label: "I consent to the collection of body readings from a wearable chest strap, including heart rate, breathing rate, body temperature, and movement, for anxiety monitoring and research (Section 3).",
                          ),
                          _consentCheck(
                            value: _cbStorage,
                            key: 'storage',
                            label: "I understand that my data will be stored in Google Cloud systems outside Sri Lanka, and I agree to this transfer under PDPA No. 9 of 2022, Section 24 (Section 4).",
                          ),
                          _consentCheck(
                            value: _cbRights,
                            key: 'rights',
                            label: "I know my rights under PDPA No. 9 of 2022, including the right to see, correct, delete, limit, or withdraw my data at any time (Section 5).",
                          ),
                          _consentCheck(
                            value: _cbVoluntary,
                            key: 'voluntary',
                            label: "I understand that joining is my choice and I may leave at any time without penalty (Section 7).",
                          ),
                          _consentCheck(
                            value: _cbLiability,
                            key: 'liability',
                            label: "I understand that this app is only for research and does not replace advice from a health professional. If I use it, I accept the risks and will not hold the developers responsible if something goes wrong.",
                          ),

                          const SizedBox(height: 14),

                          // In first-run mode, show hint banners here too.
                          if (!widget.readOnly && !_hasScrolledToBottom)
                            _scrollHint(),
                          if (!widget.readOnly && _hasScrolledToBottom && !_allChecked)
                            _checkboxHint(),

                          // Consent timestamp (readOnly only).
                          if (widget.readOnly && _consentTimestamp.isNotEmpty)
                            _timestampBadge(),

                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.kPrimaryDeep.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.gavel_rounded,
                color: AppTheme.kPrimaryDeep, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.readOnly
                  ? "View Informed Consent"
                  : "Informed Consent",
              style: GoogleFonts.poppins(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppTheme.kTextDark,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Text(
              "NHSL Review",
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FOOTER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    if (widget.readOnly) {
      // Read-only: show a plain Close / Back button.
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            label: const Text("Close"),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      );
    }

    // First-run consent button.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_hasScrolledToBottom)
            _scrollHint()
          else if (!_allChecked)
            _checkboxHint(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _canProceed ? _acceptConsent : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.kPrimaryDeep,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: _canProceed ? 4 : 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _canProceed
                        ? Icons.verified_outlined
                        : Icons.lock_outline,
                    color: _canProceed ? Colors.white : Colors.grey.shade500,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "I Consent & Continue",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: _canProceed
                          ? Colors.white
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            "Consent timestamp is recorded automatically upon confirmation.",
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHECKBOX — interactive (first run) or locked (read-only)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _consentCheck({
    required bool value,
    required String key,
    required String label,
  }) {
    final bool locked = widget.readOnly;

    // In first-run mode wire up the setter.
    void onChange(bool? v) {
      if (locked) return; // no-op when locked
      setState(() {
        switch (key) {
          case 'age':      _cbAge       = v ?? false; break;
          case 'purpose':  _cbPurpose   = v ?? false; break;
          case 'data':     _cbData      = v ?? false; break;
          case 'physio':   _cbPhysio    = v ?? false; break;
          case 'storage':  _cbStorage   = v ?? false; break;
          case 'rights':   _cbRights    = v ?? false; break;
          case 'voluntary':_cbVoluntary = v ?? false; break;
          case 'liability':_cbLiability = v ?? false; break;
        }
      });
    }

    return GestureDetector(
      onTap: locked ? null : () => onChange(!value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          // Ticked + locked → green tint. Ticked + interactive → purple tint.
          color: value
              ? (locked
                  ? Colors.green.withValues(alpha: 0.06)
                  : AppTheme.kPrimaryDeep.withValues(alpha: 0.06))
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: value
                ? (locked
                    ? Colors.green.shade400
                    : AppTheme.kPrimaryDeep.withValues(alpha: 0.45))
                : Colors.grey.shade300,
            width: value ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: locked ? null : onChange,
                activeColor:
                    locked ? Colors.green.shade600 : AppTheme.kPrimaryDeep,
                // Keep the checkmark visible even when disabled.
                fillColor: locked && value
                    ? WidgetStateProperty.all(Colors.green.shade600)
                    : null,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color:
                            value ? AppTheme.kTextDark : Colors.grey.shade700,
                        fontWeight:
                            value ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (locked && value) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.lock_outline,
                        size: 13, color: Colors.green),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // READ-ONLY WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _readOnlyBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              color: Colors.blue.shade700, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You are viewing the consent form you agreed to when joining the study. "
              "Your answers are permanently recorded and cannot be changed.",
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue.shade800,
                  height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timestampBadge() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_outlined,
              color: Colors.green.shade700, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Agreement Confirmed",
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade800),
                ),
                const SizedBox(height: 2),
                Text(
                  "Date & time: $_consentTimestamp",
                  style: TextStyle(
                      fontSize: 11.5, color: Colors.green.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HINT BANNERS (first-run only)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _scrollHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.amber.shade700, size: 17),
          const SizedBox(width: 6),
          Text(
            "Scroll to the bottom to read the full consent form",
            style: TextStyle(
                fontSize: 11,
                color: Colors.amber.shade800,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _checkboxHint() {
    final pending = [
      if (!_cbAge)       "Confirm age ≥ 18",
      if (!_cbPurpose)   "Why the study is being done and what you need to do",
      if (!_cbData)      "Information the app collects",
      if (!_cbPhysio)    "Body readings from the chest strap",
      if (!_cbStorage)   "Data stored outside Sri Lanka",
      if (!_cbRights)    "Your data rights",
      if (!_cbVoluntary) "Joining is your choice",
      if (!_cbLiability) "Research use only and responsibility",
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Please tick all boxes to continue:",
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade800),
          ),
          const SizedBox(height: 4),
          ...pending.map((p) => Text("• $p",
              style: TextStyle(
                  fontSize: 11, color: Colors.orange.shade700))),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONTENT WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _institutionBadge() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.kPrimaryDeep.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.kPrimaryDeep.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.school_outlined,
              color: AppTheme.kPrimaryDeep, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Sri Lanka Institute of Information Technology (SLIIT)",
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.kPrimaryDeep),
                ),
                const SizedBox(height: 3),
                Text(
                  "Faculty of Computing  |  Dept. of Information Technology\n"
                  "Ethics Ref: SLIIT/IT/RES/2024  |  Study ID: ANXIETY-DIGITAL-2024\n"
                  "Contact: it22130648@my.sliit.lk",
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataTable() {
    const rows = [
      ["General Location",   "Approximate location, movement speed, and how accurate the location is. Saved locations are made less exact by about 1 km.", "Every 15 min"],
      ["Screen Use",         "When the screen is turned on, turned off, or unlocked. Screen content is never saved.", "As it happens"],
      ["Phone Movement",    "Times when the phone detects a large movement. Detailed movement is not saved.", "As it happens"],
      ["Call Totals",       "Numbers of incoming, outgoing, and missed calls. No phone numbers or call content.", "Every 15 min"],
      ["Message Totals",    "Numbers of sent and received text messages. No message content.",             "Every 15 min"],
      ["App Use",           "Time spent in groups such as social or browser apps. Individual app names are not stored.", "Every 15 min"],
      ["Battery",           "Battery percentage and whether the phone is charging.",                       "Every 15 min"],
      ["Screen Tap Pressure", "How firmly the screen is pressed during a selected activity.",              "When used"],
      ["Daily Check-ins",   "Stress, anxiety, tiredness, social feelings, and current activity.",           "3 times daily"],
      ["Weekly Anxiety Check", "The 7 GAD-7 answers and total score.",                                      "Weekly"],
      ["Weekly Stress Check", "The 10 PSS-10 answers and total score.",                                     "Weekly"],
      ["About You",         "Age, gender, education, work, whether a health professional has told you that you have anxiety, and sleep quality.", "When you join"],
      ["Heart Rate",        "Heartbeats per minute from the wearable chest strap.",                         "As it happens"],
      ["Breathing Rate",    "Breaths per minute from the chest strap.",                                     "As it happens"],
      ["Body Temperature",  "Temperature reading where the chest strap touches your skin.",                 "As it happens"],
      ["Chest Strap Movement", "How much the chest strap moves.",                                           "As it happens"],
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.kPrimaryDeep.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: _tRow("Information", "What Is Stored", "How Often",
                header: true),
          ),
          ...rows.asMap().entries.map((e) {
            final last = e.key == rows.length - 1;
            return Container(
              decoration: BoxDecoration(
                color: e.key.isEven ? Colors.white : const Color(0xFFFAFAFC),
                borderRadius: last
                    ? const BorderRadius.vertical(
                        bottom: Radius.circular(10))
                    : null,
                border: const Border(
                    top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: _tRow(e.value[0], e.value[1], e.value[2]),
            );
          }),
        ],
      ),
    );
  }

  Widget _tRow(String a, String b, String c, {bool header = false}) {
    final s = TextStyle(
      fontSize: 11,
      fontWeight: header ? FontWeight.w700 : FontWeight.normal,
      color: header ? AppTheme.kPrimaryDeep : Colors.black87,
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: Text(a, style: s)),
          const SizedBox(width: 6),
          Expanded(flex: 5, child: Text(b, style: s)),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: Text(c, style: s)),
        ],
      ),
    );
  }

  Widget _rightItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppTheme.kAccentBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 15, color: AppTheme.kPrimaryDeep),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(desc,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TYPOGRAPHY ────────────────────────────────────────────────────────────

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 9, top: 2),
        child: Text(t,
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.kPrimaryDeep)),
      );

  Widget _subTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5, top: 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black87)),
      );

  Widget _paragraph(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Text(t,
            style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: Colors.grey.shade800)),
      );

  Widget _bulletItem(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5.5),
              child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                      color: AppTheme.kAccentBlue,
                      shape: BoxShape.circle)),
            ),
            const SizedBox(width: 9),
            Expanded(
                child: Text(t,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: Colors.grey.shade800))),
          ],
        ),
      );

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Divider(height: 1, color: Colors.grey.shade200),
      );
}
