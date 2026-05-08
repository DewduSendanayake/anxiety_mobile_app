import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'login_page.dart';

/// InformedConsentPage — NHSL Ethics Review Edition
///
/// Structure mirrors the standard NHSL/WHO consent template:
///   1. Study identity badge (institution, study ID)
///   2. Introduction & Purpose
///   3. Duration & Participant Involvement
///   4. Data Collected (plain-language table)
///   5. Storage, Security & Overseas Transfer
///   6. Participant Rights (PDPA No. 9 of 2022)
///   7. Risks & Benefits
///   8. Voluntariness & Withdrawal
///   9. Ethical Approval statement
///  10. Six mandatory checkbox declarations
///  11. Locked "I Consent & Continue" button
///      (unlocks only when ALL boxes ticked AND full scroll reached)
class InformedConsentPage extends StatefulWidget {
  const InformedConsentPage({super.key});

  @override
  State<InformedConsentPage> createState() => _InformedConsentPageState();
}

class _InformedConsentPageState extends State<InformedConsentPage> {
  bool _hasScrolledToBottom = false;
  final ScrollController _scrollController = ScrollController();

  // Six explicit declarations — all must be ticked.
  bool _cbAge       = false;
  bool _cbPurpose   = false;
  bool _cbData      = false;
  bool _cbStorage   = false;
  bool _cbRights    = false;
  bool _cbVoluntary = false;

  bool get _allChecked =>
      _cbAge && _cbPurpose && _cbData && _cbStorage && _cbRights && _cbVoluntary;

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
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _acceptConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('consent_accepted', true);
    await prefs.setString('consent_timestamp', DateTime.now().toIso8601String());
    // Persist which declarations were explicitly checked for audit trail.
    await prefs.setBool('consent_cb_age',       _cbAge);
    await prefs.setBool('consent_cb_purpose',   _cbPurpose);
    await prefs.setBool('consent_cb_data',      _cbData);
    await prefs.setBool('consent_cb_storage',   _cbStorage);
    await prefs.setBool('consent_cb_rights',    _cbRights);
    await prefs.setBool('consent_cb_voluntary', _cbVoluntary);

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
                    color: Colors.white.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
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

                          // ── S1: Introduction ───────────────────────────
                          _sectionTitle("1. Introduction & Purpose"),
                          _paragraph(
                            "You are being invited to voluntarily participate in an approved research study "
                            "conducted by the Sri Lanka Institute of Information Technology (SLIIT). "
                            "Before you decide to participate, please read this form carefully. "
                            "You may take as much time as you need.",
                          ),
                          _paragraph(
                            "The purpose of this study is to investigate whether passively collected smartphone "
                            "data — such as movement patterns, screen usage, communication frequency, and "
                            "self-reported mood — can serve as reliable digital biomarkers for detecting and "
                            "monitoring anxiety levels in young adults over a 12-month period.",
                          ),
                          _divider(),

                          // ── S2: Duration & Involvement ─────────────────
                          _sectionTitle("2. Study Duration & Your Involvement"),
                          _bulletItem("Duration: 12 months from your enrolment date."),
                          _bulletItem("You will keep this application installed and running on your Android device throughout the study."),
                          _bulletItem("3 brief daily mood check-ins (morning, afternoon, evening) — approx. 1–2 minutes each, at times you configure."),
                          _bulletItem("A validated GAD-7 questionnaire (7 questions, ~2 min) sent every week."),
                          _bulletItem("A validated PSS-10 questionnaire (10 questions, ~3 min) sent weekly."),
                          _bulletItem("A one-time demographics survey at enrolment (age, gender, education, etc.)."),
                          _divider(),

                          // ── S3: Data Table ─────────────────────────────
                          _sectionTitle("3. What Data Will Be Collected?"),
                          _paragraph(
                            "The table below lists every category of data collected. "
                            "The application does NOT read the content of any SMS or phone call.",
                          ),
                          _dataTable(),
                          _divider(),

                          // ── S4: Storage ─────────────────────────────────
                          _sectionTitle("4. Data Storage, Security & Overseas Transfer"),
                          _paragraph(
                            "All data is transmitted over encrypted HTTPS and stored on Google Cloud "
                            "infrastructure operated by Google LLC (servers located outside Sri Lanka).",
                          ),
                          _paragraph(
                            "This overseas transfer is conducted under the scientific-research exemption "
                            "of the Sri Lanka Personal Data Protection Act (PDPA) No. 9 of 2022, Section 24.",
                          ),
                          _bulletItem("Your real name and phone number are NEVER stored on our research servers."),
                          _bulletItem("All records are linked only to a randomly assigned Participant ID."),
                          _bulletItem("GPS coordinates are fuzzy-rounded to ±1 km before storage to protect privacy."),
                          _bulletItem("Application package names are replaced with anonymised categories (e.g., 'Social_Media') before storage."),
                          _bulletItem("Access to the data is restricted to the named research team at SLIIT."),
                          _bulletItem("Data will be retained for a maximum of 5 years after study completion, then permanently deleted."),
                          _divider(),

                          // ── S5: Rights ──────────────────────────────────
                          _sectionTitle("5. Your Rights as a Data Subject (PDPA No. 9 of 2022)"),
                          _paragraph("You have the following rights at any time:"),
                          _rightItem(Icons.visibility_outlined, "Right of Access",
                              "Request a full copy of all data collected about you."),
                          _rightItem(Icons.edit_outlined, "Right to Rectification",
                              "Request correction of inaccurate personal data."),
                          _rightItem(Icons.delete_outline, "Right to Erasure",
                              "Request complete deletion of your data at any time without penalty."),
                          _rightItem(Icons.pause_circle_outline, "Right to Restriction",
                              "Request that we restrict processing while a complaint is pending."),
                          _rightItem(Icons.exit_to_app_outlined, "Right to Withdraw",
                              "Withdraw from the study at any time without giving any reason and without adverse consequences."),
                          _paragraph(
                            "To exercise any right: email it22130648@my.sliit.lk and include your Participant ID.",
                          ),
                          _divider(),

                          // ── S6: Risks & Benefits ────────────────────────
                          _sectionTitle("6. Potential Risks & Benefits"),
                          _subTitle("Risks"),
                          _bulletItem("Minimal risk — the app runs quietly in the background and does not interfere with normal phone use."),
                          _bulletItem("Minor battery drain estimated at less than 5% additional consumption per day."),
                          _bulletItem("Some mood/anxiety questions may feel emotionally activating. You are not required to answer any question that makes you uncomfortable."),
                          _subTitle("Benefits"),
                          _bulletItem("You directly contribute to advancing digital mental health research in a South Asian context."),
                          _bulletItem("Findings may inform future clinically validated anxiety screening tools."),
                          _bulletItem("There is no direct financial compensation for participation."),
                          _divider(),

                          // ── S7: Voluntariness ───────────────────────────
                          _sectionTitle("7. Voluntary Participation & Withdrawal"),
                          _paragraph(
                            "Participation is entirely voluntary. You may withdraw at any time without giving "
                            "a reason and without any negative consequences to your relationship with SLIIT or "
                            "any other institution. To withdraw, uninstall the application and email the "
                            "research team to request deletion of your data.",
                          ),
                          _divider(),

                          // ── S8: Ethical Approval ────────────────────────
                          _sectionTitle("8. Ethical Approval"),
                          _paragraph(
                            "This study has been designed in accordance with the ethical principles of the "
                            "Declaration of Helsinki (2013 revision), ICH Good Clinical Practice guidelines, "
                            "and the Sri Lanka PDPA No. 9 of 2022. Ethical review and approval is being sought "
                            "from the National Hospital of Sri Lanka (NHSL) Ethics Review Committee and the "
                            "SLIIT Institutional Review Board (IRB).",
                          ),
                          _paragraph(
                            "Ethics Ref: SLIIT/IT/RES/2024 | Study ID: ANXIETY-DIGITAL-2024",
                          ),
                          _divider(),

                          // ── S9: Declarations ────────────────────────────
                          _sectionTitle("9. Declaration of Informed Consent"),
                          _paragraph(
                            "Please read each statement below carefully and tick the box to confirm your "
                            "understanding and agreement. All six declarations are required before you can proceed.",
                          ),
                          const SizedBox(height: 6),

                          _consentCheck(
                            value: _cbAge,
                            onChange: (v) => setState(() => _cbAge = v ?? false),
                            label:
                                "I confirm that I am 18 years of age or older and legally able to provide informed consent.",
                          ),
                          _consentCheck(
                            value: _cbPurpose,
                            onChange: (v) => setState(() => _cbPurpose = v ?? false),
                            label:
                                "I have read and understood the purpose, procedures, and 12-month duration of this research study (Sections 1 & 2).",
                          ),
                          _consentCheck(
                            value: _cbData,
                            onChange: (v) => setState(() => _cbData = v ?? false),
                            label:
                                "I understand what data categories are collected from my device, including location, sensor data, communication metadata, and self-report responses, and I consent to this collection (Section 3).",
                          ),
                          _consentCheck(
                            value: _cbStorage,
                            onChange: (v) => setState(() => _cbStorage = v ?? false),
                            label:
                                "I understand that my data will be stored on overseas Google Cloud servers and I explicitly consent to this overseas transfer as permitted under PDPA No. 9 of 2022, Section 24 (Section 4).",
                          ),
                          _consentCheck(
                            value: _cbRights,
                            onChange: (v) => setState(() => _cbRights = v ?? false),
                            label:
                                "I am aware of my rights as a data subject under PDPA No. 9 of 2022, including the right to access, rectify, erase, restrict, and withdraw my data at any time (Section 5).",
                          ),
                          _consentCheck(
                            value: _cbVoluntary,
                            onChange: (v) => setState(() => _cbVoluntary = v ?? false),
                            label:
                                "I understand that participation is entirely voluntary and that I may withdraw at any time without penalty or adverse consequence (Section 7).",
                          ),

                          const SizedBox(height: 14),
                          if (!_hasScrolledToBottom) _scrollHint(),
                          if (_hasScrolledToBottom && !_allChecked) _checkboxHint(),
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
              color: AppTheme.kPrimaryDeep.withOpacity(0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.gavel_rounded,
                color: AppTheme.kPrimaryDeep, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Informed Consent",
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
              color: Colors.green.withOpacity(0.1),
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
                    _canProceed ? Icons.verified_outlined : Icons.lock_outline,
                    color: _canProceed ? Colors.white : Colors.grey.shade500,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "I Consent & Continue",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color:
                          _canProceed ? Colors.white : Colors.grey.shade500,
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
  // COMPONENTS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _institutionBadge() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.kPrimaryDeep.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.kPrimaryDeep.withOpacity(0.18)),
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
                Text(
                  "Sri Lanka Institute of Information Technology (SLIIT)",
                  style: const TextStyle(
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

  Widget _consentCheck({
    required bool value,
    required ValueChanged<bool?> onChange,
    required String label,
  }) {
    return GestureDetector(
      onTap: () => onChange(!value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: value
              ? AppTheme.kPrimaryDeep.withOpacity(0.06)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: value
                ? AppTheme.kPrimaryDeep.withOpacity(0.45)
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
                onChanged: onChange,
                activeColor: AppTheme.kPrimaryDeep,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: value
                      ? AppTheme.kTextDark
                      : Colors.grey.shade700,
                  fontWeight:
                      value ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataTable() {
    const rows = [
      ["GPS Location", "Fuzzy-rounded lat/lng (±1 km), speed, accuracy only.", "Every 15 min"],
      ["Screen Events", "Screen on, off, unlock. No screen content ever.", "Real-time"],
      ["Motion (Accel.)", "Significant-movement events above threshold. No raw IMU stream.", "Real-time"],
      ["Call Metadata", "Counts: incoming / outgoing / missed / rejected in 24 h. No numbers or content.", "Every 15 min"],
      ["SMS Metadata", "Count of sent / received SMS today. No message content.", "Every 15 min"],
      ["App Usage", "Time in anonymised categories (Social, Browser, etc.). Package names not stored.", "Every 15 min"],
      ["Battery Status", "Level % and charging state.", "Every 15 min"],
      ["Touch Pressure", "Pressure reading when dashboard orb is held. Physiological proxy.", "On interaction"],
      ["EMA Ratings", "Stress, anxiety, fatigue, social (1–5) + activity context.", "3× daily"],
      ["GAD-7 Score", "7-item validated scale — total score + per-item responses.", "Weekly"],
      ["PSS-10 Score", "10-item validated scale — total score + per-item responses.", "Weekly"],
      ["Demographics", "Age, gender, education, employment, diagnosis, sleep quality. One-time only.", "Enrolment"],
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
              color: AppTheme.kPrimaryDeep.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: _tRow("Data Type", "What Is Stored", "Frequency",
                header: true),
          ),
          ...rows.asMap().entries.map((e) {
            final last = e.key == rows.length - 1;
            return Container(
              decoration: BoxDecoration(
                color:
                    e.key.isEven ? Colors.white : const Color(0xFFFAFAFC),
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
              color: AppTheme.kAccentBlue.withOpacity(0.15),
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
      if (!_cbPurpose)   "Study purpose & procedures",
      if (!_cbData)      "Data collection",
      if (!_cbStorage)   "Overseas storage",
      if (!_cbRights)    "Your data rights",
      if (!_cbVoluntary) "Voluntary participation",
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
            "Please tick all declaration boxes to enable the consent button:",
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade800),
          ),
          const SizedBox(height: 4),
          ...pending.map((p) => Text(
                "• $p",
                style: TextStyle(
                    fontSize: 11, color: Colors.orange.shade700),
              )),
        ],
      ),
    );
  }

  // ── TYPOGRAPHY ─────────────────────────────────────────────────────────

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
                fontSize: 12.5, height: 1.55, color: Colors.grey.shade800)),
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