import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_service_helper.dart';
import 'theme/app_theme.dart';
import 'pages/main_navigation_page.dart';
import 'pages/data_rights_page.dart';
import 'services/background/service_config.dart';

class ProfilePage extends StatefulWidget {
  final bool isTab;
  const ProfilePage({super.key, this.isTab = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isEditing = false;
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _isEditing = !widget.isTab; // Tab mode starts in view; standalone starts in edit
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id') ?? '';
    final profileJson = prefs.getString('user_profile_data');
    if (profileJson != null) {
      final data = jsonDecode(profileJson);
      setState(() {
        _userId = uid;
        _ageController.text = data['age'] ?? '';
        _gender = data['gender'];
        _maritalStatus = data['marital_status'];
        _employmentStatus = data['employment_status'];
        _financialStatus = data['financial_status'];
        _educationLevel = data['education_level'];
        _livingSituation = data['living_situation'];
        _anxietyDiagnosis = data['anxiety_diagnosis'];
        _onMedication = data['on_medication'];
        _sleepQuality = double.tryParse(data['sleep_quality_rating'] ?? '3') ?? 3;
        
        _morningTime = TimeOfDay(
          hour: prefs.getInt('ema_morning_hour') ?? 9,
          minute: prefs.getInt('ema_morning_minute') ?? 0,
        );
        _afternoonTime = TimeOfDay(
          hour: prefs.getInt('ema_afternoon_hour') ?? 14,
          minute: prefs.getInt('ema_afternoon_minute') ?? 0,
        );
        _eveningTime = TimeOfDay(
          hour: prefs.getInt('ema_evening_hour') ?? 20,
          minute: prefs.getInt('ema_evening_minute') ?? 0,
        );
      });
    } else {
      setState(() => _userId = uid);
    }
  }

  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // --- Form fields ---
  final _ageController = TextEditingController();
  String? _gender;
  String? _maritalStatus;
  String? _employmentStatus;
  String? _financialStatus;
  String? _educationLevel;
  String? _livingSituation;
  String? _anxietyDiagnosis;
  String? _onMedication;
  double _sleepQuality = 3;

  // --- Notification Times ---
  TimeOfDay _morningTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _afternoonTime = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay _eveningTime = const TimeOfDay(hour: 20, minute: 0);

  static const _genders = ['Male', 'Female', 'Non-binary', 'Prefer not to say'];
  static const _maritalStatuses = [
    'Single',
    'Married',
    'Divorced',
    'Widowed',
    'Other',
  ];
  static const _employmentStatuses = [
    'Student',
    'Employed (Full-time)',
    'Employed (Part-time)',
    'Unemployed',
    'Self-employed',
  ];
  static const _financialStatuses = [
    'Low income',
    'Lower-middle income',
    'Middle income',
    'Upper-middle income',
    'High income',
  ];
  static const _educationLevels = [
    'O/L or below',
    'A/L',
    'Undergraduate',
    'Postgraduate',
    'Other',
  ];
  static const _livingSituations = [
    'Alone',
    'With family',
    'With partner/spouse',
    'With friends/roommates',
    'University hostel',
    'Other',
  ];

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_gender == null ||
        _maritalStatus == null ||
        _employmentStatus == null ||
        _financialStatus == null ||
        _educationLevel == null ||
        _livingSituation == null ||
        _anxietyDiagnosis == null ||
        _onMedication == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id') ?? 'Unknown';

    final profile = {
      'age': _ageController.text.trim(),
      'gender': _gender,
      'marital_status': _maritalStatus,
      'employment_status': _employmentStatus,
      'financial_status': _financialStatus,
      'education_level': _educationLevel,
      'living_situation': _livingSituation,
      'anxiety_diagnosis': _anxietyDiagnosis,
      'on_medication': _onMedication,
      'sleep_quality_rating': _sleepQuality.round().toString(),
    };

    await BackgroundServiceHelper.sendToSheet(
      uid,
      'Demographics',
      jsonEncode(profile),
    );

    await prefs.setBool('profile_complete', true);
    await prefs.setString('user_profile_data', jsonEncode(profile));

    // Save notification times
    await prefs.setInt('ema_morning_hour', _morningTime.hour);
    await prefs.setInt('ema_morning_minute', _morningTime.minute);
    await prefs.setInt('ema_afternoon_hour', _afternoonTime.hour);
    await prefs.setInt('ema_afternoon_minute', _afternoonTime.minute);
    await prefs.setInt('ema_evening_hour', _eveningTime.hour);
    await prefs.setInt('ema_evening_minute', _eveningTime.minute);

    if (mounted) {
      setState(() => _isSaving = false);
      if (widget.isTab) {
        // In tab mode, go back to view mode after save
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile updated successfully!',
                style: GoogleFonts.poppins(fontSize: 13)),
            backgroundColor: const Color(0xFF5E60CE),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MainNavigationPage(userId: uid)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tab mode with data loaded: show attractive profile view or edit form
    if (widget.isTab && !_isEditing) {
      return _buildProfileView();
    }
    return _buildEditForm();
  }

  // ══════════════════════════════════════════════════════════════
  // ATTRACTIVE PROFILE VIEW (Tab Mode)
  // ══════════════════════════════════════════════════════════════

  Widget _buildProfileView() {
    const labels = ['Very Poor', 'Poor', 'Fair', 'Good', 'Excellent'];
    final sleepLabel = labels[(_sleepQuality.round() - 1).clamp(0, 4)];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // ── Gradient Header with Avatar ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 60, bottom: 30),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(36),
                  bottomRight: Radius.circular(36),
                ),
              ),
              child: Column(
                children: [
                  // Avatar
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 3),
                    ),
                    child: Icon(
                      _gender == 'Male' ? Icons.face_rounded
                          : _gender == 'Female' ? Icons.face_3_rounded
                          : Icons.person_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Participant',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _userId.isNotEmpty ? 'ID: $_userId' : 'ID: Not assigned',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Edit button
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _isEditing = true),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text('Edit Profile', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF5E60CE),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Info Cards ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _infoCard('Personal Info', Icons.person_outline_rounded, [
                    _infoRow(Icons.cake_rounded, 'Age', _ageController.text.isNotEmpty ? '${_ageController.text} years' : 'Not set'),
                    _infoRow(Icons.wc_rounded, 'Gender', _gender ?? 'Not set'),
                    _infoRow(Icons.favorite_rounded, 'Marital Status', _maritalStatus ?? 'Not set'),
                  ]),
                  const SizedBox(height: 14),
                  _infoCard('Professional', Icons.work_outline_rounded, [
                    _infoRow(Icons.business_center_rounded, 'Employment', _employmentStatus ?? 'Not set'),
                    _infoRow(Icons.account_balance_wallet_rounded, 'Financial Status', _financialStatus ?? 'Not set'),
                    _infoRow(Icons.school_rounded, 'Education', _educationLevel ?? 'Not set'),
                    _infoRow(Icons.home_rounded, 'Living Situation', _livingSituation ?? 'Not set'),
                  ]),
                  const SizedBox(height: 14),
                  _infoCard('Health', Icons.health_and_safety_outlined, [
                    _infoRow(Icons.psychology_rounded, 'Anxiety Diagnosis', _anxietyDiagnosis ?? 'Not set'),
                    _infoRow(Icons.medication_rounded, 'On Medication', _onMedication ?? 'Not set'),
                    _infoRow(Icons.bedtime_rounded, 'Sleep Quality', sleepLabel),
                  ]),
                  const SizedBox(height: 14),
                  _infoCard('Check-in Schedule', Icons.schedule_rounded, [
                    _infoRow(Icons.wb_sunny_rounded, 'Morning', _morningTime.format(context)),
                    _infoRow(Icons.wb_cloudy_rounded, 'Afternoon', _afternoonTime.format(context)),
                    _infoRow(Icons.nightlight_round, 'Evening', _eveningTime.format(context)),
                  ]),
                  const SizedBox(height: 14),
                  _buildPrivacyCard(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String title, IconData icon, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.kPrimaryDeep.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppTheme.kPrimaryDeep, size: 20),
              ),
              const SizedBox(width: 12),
              Text(title, style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.kTextDark)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.kTextLight),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: GoogleFonts.poppins(
              fontSize: 13, color: AppTheme.kTextLight)),
          ),
          Text(value, style: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.kTextDark)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // EDIT FORM (original form, used in both standalone and edit mode)
  // ══════════════════════════════════════════════════════════════

  Widget _buildEditForm() {
    return Scaffold(
      backgroundColor: AppTheme.kBgTop,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Back to view button in tab mode
              if (widget.isTab) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _isEditing = false),
                    icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
                    label: Text('Back to Profile', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.kPrimaryDeep),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              const Icon(Icons.person_pin, size: 52, color: AppTheme.kPrimaryDeep),
              const SizedBox(height: 12),
              const Text(
                'Participant Profile',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Text(
                'This information is collected once and kept strictly confidential for research purposes.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 28),

              _sectionLabel('Age'),
              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: _inputDec('Enter your age'),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final n = int.tryParse(v);
                  if (n == null || n < 16 || n > 60) return 'Enter a valid age (16–60)';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _sectionLabel('Gender'),
              _dropdown(_genders, _gender, (v) => setState(() => _gender = v)),
              const SizedBox(height: 16),

              _sectionLabel('Marital Status'),
              _dropdown(_maritalStatuses, _maritalStatus, (v) => setState(() => _maritalStatus = v)),
              const SizedBox(height: 16),

              _sectionLabel('Employment Status'),
              _dropdown(_employmentStatuses, _employmentStatus, (v) => setState(() => _employmentStatus = v)),
              const SizedBox(height: 16),

              _sectionLabel('Financial Status'),
              _dropdown(_financialStatuses, _financialStatus, (v) => setState(() => _financialStatus = v)),
              const SizedBox(height: 16),

              _sectionLabel('Highest Education Level'),
              _dropdown(_educationLevels, _educationLevel, (v) => setState(() => _educationLevel = v)),
              const SizedBox(height: 16),

              _sectionLabel('Living Situation'),
              _dropdown(_livingSituations, _livingSituation, (v) => setState(() => _livingSituation = v)),
              const SizedBox(height: 16),

              _sectionLabel('Have you been diagnosed with an anxiety disorder?'),
              _radioGroup(['Yes', 'No', 'Unsure'], _anxietyDiagnosis, (v) => setState(() => _anxietyDiagnosis = v)),
              const SizedBox(height: 16),

              _sectionLabel('Are you currently on medication for anxiety/mental health?'),
              _radioGroup(['Yes', 'No', 'Prefer not to say'], _onMedication, (v) => setState(() => _onMedication = v)),
              const SizedBox(height: 16),

              _sectionLabel('How would you rate your typical sleep quality? (1 = Very Poor, 5 = Excellent)'),
              const SizedBox(height: 8),
              _buildSlider(),
              const SizedBox(height: 32),

              const Divider(),
              const SizedBox(height: 24),
              const Text('Daily Check-in Preferences', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Choose when you want to be prompted for your daily anxiety check-ins (1–5 scale).',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 20),

              _timeTile('Morning Check-in', _morningTime, (t) => setState(() => _morningTime = t), Icons.wb_sunny_outlined),
              _timeTile('Afternoon Check-in', _afternoonTime, (t) => setState(() => _afternoonTime = t), Icons.wb_cloudy_outlined),
              _timeTile('Evening Check-in', _eveningTime, (t) => setState(() => _eveningTime = t), Icons.nightlight_round_outlined),
              const SizedBox(height: 40),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              const Text('Privacy & Data Rights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildPrivacyCard(),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  child: _isSaving
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save & Continue'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.kPrimaryDeep, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _dropdown(
    List<String> items,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: const Text('Select an option'),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  /// FIX: replaced deprecated RadioListTile groupValue/onChanged
  /// with RadioGroup ancestor pattern (Flutter 3.32+)
  Widget _radioGroup(
    List<String> options,
    String? groupValue,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: RadioGroup<String>(
        groupValue: groupValue,
        onChanged: onChanged,
        child: Column(
          children: options
              .map(
                (o) => RadioListTile<String>(
                  title: Text(o),
                  value: o,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildSlider() {
    const labels = ['Very Poor', 'Poor', 'Fair', 'Good', 'Excellent'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Slider(
            value: _sleepQuality,
            min: 1,
            max: 5,
            divisions: 4,
            activeColor: AppTheme.kPrimaryDeep,
            label: labels[_sleepQuality.round() - 1],
            onChanged: (v) => setState(() => _sleepQuality = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map(
                  (l) => Text(
                    l,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _timeTile(
    String label,
    TimeOfDay time,
    ValueChanged<TimeOfDay> onChanged,
    IconData icon,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.kPrimaryDeep),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.kPrimaryDeep.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            time.format(context),
            style: const TextStyle(
              color: AppTheme.kPrimaryDeep,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        onTap: () async {
          final picked = await showTimePicker(context: context, initialTime: time);
          if (picked != null) onChanged(picked);
        },
      ),
    );
  }
  Widget _buildPrivacyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_outlined, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text(
                "Consent Status: Active",
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Your data is collected anonymously using a Participant ID. "
            "All identifiers are kept separate from health data as per PDPA guidelines.",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DataRightsPage()),
              ),
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: const Text('Manage Data Rights & Privacy'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.kPrimaryDeep,
                side: const BorderSide(color: AppTheme.kPrimaryDeep),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Contact: ${ServiceConfig.researchTeamEmail}",
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

}
