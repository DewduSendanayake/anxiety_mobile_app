import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/background/service_config.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.kBgTop,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.kPrimaryDeep.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'v${ServiceConfig.consentVersion}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.kPrimaryDeep),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _header(),
          const SizedBox(height: 20),
          _section('1. Who Is Responsible for Your Data',
            '${ServiceConfig.dataController}\n'
            'Lead researcher: ${ServiceConfig.piName}\n'
            'Email: ${ServiceConfig.piEmail}\n\n'
            'This organization is legally responsible for your data. It must use your personal '
            'data according to the Sri Lanka Personal Data '
            'Protection Act (PDPA), No. 9 of 2022.',
          ),
          _section('2. Why We Are Allowed to Use Your Data',
            'Sri Lanka\'s data protection law allows us to use your data for these reasons:\n\n'
            '• Your agreement: You agreed through the consent form in the app.\n'
            '• Scientific research: The data is needed for approved research intended to benefit the public, '
            'and steps are taken to protect it.\n\n'
            'Study approval: ${ServiceConfig.ercApprovalNumber}\n'
            'Approved by: ${ServiceConfig.ercName}',
          ),
          _section('3. Information We Collect',
            'We collect the following types of information:\n\n'
            'Your Check-in Answers:\n'
            '• GAD-7 weekly anxiety check answers and score\n'
            '• PSS-10 weekly stress check answers and score\n'
            '• Short mood check-ins three times a day\n'
            '• How firmly you tap the screen during a check-in\n\n'
            'Phone Data:\n'
            '• When the screen is turned on, turned off, or unlocked\n'
            '• How much the phone moves\n'
            '• Battery level and whether the phone is charging\n\n'
            'Calls and Messages (totals only):\n'
            '• Number of incoming/outgoing/missed calls\n'
            '• Number of sent/received SMS messages\n'
            '(No names, numbers, or content are collected)\n\n'
            'App Usage:\n'
            '• Time spent in app categories (Social Media, Browser, etc.)\n'
            '(Individual app names are replaced with categories)\n\n'
            'Location:\n'
            '• An approximate location checked from time to time\n'
            '(The saved location is made less exact by about 1 km)\n\n'
            'About You (collected once):\n'
            '• Age, gender, marital status, employment, education\n'
            '• Living situation, whether a health professional has told you that you have anxiety, and whether you take medicine\n'
            '• How well you feel you sleep',
          ),
          _section('4. Data We Do NOT Collect',
            '• Your real name, phone number, or email address\n'
            '• SMS or call content\n'
            '• Contact lists or address books\n'
            '• Photos, videos, or camera data\n'
            '• Browsing history or search queries\n'
            '• Passwords or financial information\n'
            '• Social media account details',
          ),
          _section('5. How We Use Your Data',
            'Your data is used only for:\n\n'
            '• Finding phone-use patterns that may be linked with anxiety\n'
            '• Developing computer systems that look for anxiety changes\n'
            '• Publishing research findings that group many people together and do not identify you\n'
            '• Improving ways phones may support mental health\n\n'
            'We do NOT use your data for:\n'
            '• Marketing or advertising\n'
            '• Selling to third parties\n'
            '• Making automatic decisions about you from a personal profile\n'
            '• Diagnosing or treating a health condition',
          ),
          _section('6. Data Storage & Security',
            'Storage: Data is stored in Google Cloud using Google Sheets '
            'and Google Apps Script. It is protected while it is sent over the internet.\n\n'
            'Identity protection: All data is linked only to your Participant ID. '
            'Your real identity is not stored with the research data.\n\n'
            'Who can see it: Only approved members of the research team '
            '(${ServiceConfig.piAffiliation}) can see the data.\n\n'
            'Steps used to protect your privacy:\n'
            '• Saved locations made less exact by about 1 km\n'
            '• App names replaced with categories\n'
            '• Communication data limited to counts\n'
            '• No message content or contact names stored',
          ),
          _section('7. Data Stored Outside Sri Lanka',
            'Your data, stored under a Participant ID instead of your name, may be transferred to Google Cloud '
            'storage systems outside Sri Lanka.\n\n'
            'Section 25 of the PDPA requires steps to protect this data, including:\n\n'
            '• Your name is not attached to the transferred data\n'
            '• Your data is protected while it is sent over the internet\n'
            '• Only approved researchers can access it\n'
            '• You agreed to storage outside Sri Lanka',
          ),
          _section('8. How Long We Keep Your Data',
            'Your data will be kept for ${ServiceConfig.dataRetentionPeriod}.\n\n'
            'After this period, all data associated with your Participant ID '
            'will be permanently deleted from all storage systems.\n\n'
            'Grouped research results that cannot be linked back to you '
            'may be kept without a fixed end date for future research.',
          ),
          _section('9. Your Rights',
            'Under the PDPA, you have the following rights:\n\n'
            'See your data (Section 17): Ask for a copy of your data.\n\n'
            'Correct your data (Section 18): Ask us to correct data that is wrong.\n\n'
            'Delete your data (Section 19): Ask us to delete your data.\n\n'
            'Leave the study (Section 5): Leave at any time without giving a reason.\n\n'
            'Stop a specific use (Section 20): Ask us to stop using your data in a specific way.\n\n'
            'Make a complaint: Contact the Data Protection Authority of Sri Lanka.\n\n'
            'Response Time: We will respond to your request within 21 business '
            'days as required by the PDPA.\n\n'
            'To use these rights, open Your Data and Privacy in the app '
            'or contact: ${ServiceConfig.researchTeamEmail}',
          ),
          _section('10. Data Sharing',
            'We may share your data only in the following circumstances:\n\n'
            '• Research results that group many people together and do not identify you\n'
            '• With the Ethics Review Committee so it can check that the study is run properly\n'
            '• If required by law or court order\n\n'
            'We will NEVER sell your data or share data that could identify you '
            'outside the research team unless you clearly agree.',
          ),
          _section('11. Changes to This Policy',
            'We may update this privacy policy to reflect changes in our '
            'practices or legal requirements. The version number and date '
            'at the top of this document indicate the latest revision.\n\n'
            'Important changes will be shared through a notification in the app.\n\n'
            'Current Version: ${ServiceConfig.consentVersion}\n'
            'Last Updated: ${ServiceConfig.consentDate}',
          ),
          _section('12. Contact Information',
            'Lead researcher:\n'
            '${ServiceConfig.piName}\n'
            '${ServiceConfig.piEmail}\n\n'
            'Research Supervisor:\n'
            '${ServiceConfig.supervisorName}\n'
            '${ServiceConfig.supervisorEmail}\n\n'
            'Ethics Review Committee:\n'
            '${ServiceConfig.ercName}\n'
            '${ServiceConfig.ercSecretaryEmail}\n\n'
            'Data Controller:\n'
            '${ServiceConfig.dataController}\n'
            '${ServiceConfig.researchTeamEmail}',
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.kPrimaryDeep.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Privacy Policy',
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.kPrimaryDeep),
          ),
          const SizedBox(height: 4),
          Text(ServiceConfig.studyTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'This privacy policy explains how we collect, use, store, and protect '
            'your personal data in compliance with the Sri Lanka Personal Data '
            'Protection Act (PDPA), No. 9 of 2022.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 8),
          Text(content, style: TextStyle(fontSize: 13, height: 1.6, color: Colors.grey.shade800)),
        ],
      ),
    );
  }
}
