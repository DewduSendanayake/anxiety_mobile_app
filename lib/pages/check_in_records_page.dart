import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/clinician_insight_service.dart';

class CheckInRecordsPage extends StatefulWidget {
  final String userId;

  const CheckInRecordsPage({super.key, required this.userId});

  @override
  State<CheckInRecordsPage> createState() => _CheckInRecordsPageState();
}

class _CheckInRecordsPageState extends State<CheckInRecordsPage> {
  bool _loading = true;
  List<CheckInRecord> _records = const [];
  Map<String, dynamic>? _clinicianHandoff;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await ClinicianInsightService.loadCheckInRecords(
      widget.userId,
      days: 30,
    );
    final handoff = await ClinicianInsightService.buildAndCache(widget.userId);
    if (!mounted) return;
    setState(() {
      _records = records;
      _clinicianHandoff = handoff;
      _loading = false;
    });
  }

  Map<String, dynamic> get _thirtyDaySummary {
    final checkIns = _clinicianHandoff?['check_ins'];
    if (checkIns is! Map) return <String, dynamic>{};
    final summary = checkIns['thirty_day'];
    return summary is Map ? Map<String, dynamic>.from(summary) : <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F5FF),
        elevation: 0,
        title: Text(
          'Check-in records',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2D3142),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                children: [
                  _summaryCard(),
                  const SizedBox(height: 14),
                  _clinicianContextCard(),
                  const SizedBox(height: 20),
                  Text(
                    'Recent check-ins',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2D3142),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_records.isEmpty)
                    _emptyCard()
                  else
                    for (final record in _records) ...[
                      _recordCard(record),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 8),
                  _disclaimer(),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard() {
    final summary = _thirtyDaySummary;
    final events = (summary['events'] as num?)?.toInt() ?? 0;
    final answered = (summary['answered'] as num?)?.toInt() ?? 0;
    final confirmed = (summary['confirmed_anxiety'] as num?)?.toInt() ?? 0;
    final followups = (summary['followups_answered'] as num?)?.toInt() ?? 0;
    final better = (summary['felt_better_count'] as num?)?.toInt() ?? 0;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: Color(0xFF6D5BD0)),
              const SizedBox(width: 9),
              Text(
                'Last 30 days',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2D3142),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip('$events', 'check-ins'),
              _statChip('$answered', 'answered'),
              _statChip('$confirmed', 'felt anxious'),
              _statChip('$better / $followups', 'felt better later'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'These counts summarize your answers to Aura check-ins. A detected change is not automatically an anxiety episode.',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              height: 1.45,
              color: const Color(0xFF75798C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clinicianContextCard() {
    final summary = _thirtyDaySummary;
    final context = summary['common_context']?.toString();
    final helpful = summary['most_helpful_action']?.toString();
    final rate = (summary['confirmation_rate'] as num?)?.toDouble();
    final betterRate = (summary['felt_better_rate'] as num?)?.toDouble();

    final behavioral = _clinicianHandoff?['behavioral_context'];
    final behavioralMap = behavioral is Map
        ? Map<String, dynamic>.from(behavioral)
        : <String, dynamic>{};
    final change = behavioralMap['change_detection'];
    final changeMap = change is Map
        ? Map<String, dynamic>.from(change)
        : <String, dynamic>{};

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medical_information_outlined, color: Color(0xFF2D9C79)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Useful context for a clinician',
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2D3142),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Aura prepares a compact summary instead of sharing raw location or app-level data.',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              height: 1.45,
              color: const Color(0xFF75798C),
            ),
          ),
          if (rate != null) _insightRow('Check-ins confirming anxiety', '${(rate * 100).round()}% of answered check-ins'),
          if (context != null) _insightRow('Common situation', context),
          if (helpful != null) _insightRow('Action linked with feeling better', helpful),
          if (betterRate != null)
            _insightRow('Five-minute follow-up', '${(betterRate * 100).round()}% reported feeling better'),
          if (changeMap['detected'] == true)
            _insightRow(
              'Behavioural pattern change',
              '${changeMap['feature'] ?? 'A behaviour'} was ${changeMap['direction'] ?? 'different'} from the personal baseline',
            ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EDFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Component 2 remains not validated for clinical risk scoring and contributes no numerical score to the multimodal composite.',
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                height: 1.45,
                color: const Color(0xFF625B82),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordCard(CheckInRecord record) {
    final response = record.confirmedAnxious == null
        ? 'Not answered'
        : record.confirmedAnxious == true
            ? 'Felt anxious'
            : 'Did not feel anxious';
    final action = record.actionTaken;
    final followup = record.feltBetter == null
        ? null
        : record.feltBetter == true
            ? 'Felt better at follow-up'
            : 'Did not feel better at follow-up';

    return _card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 6),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF6D5BD0).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF6D5BD0)),
          ),
          title: Text(
            response,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2D3142),
            ),
          ),
          subtitle: Text(
            _formatDateTime(record.detectedAt),
            style: GoogleFonts.poppins(fontSize: 10.5, color: const Color(0xFF8B8FA3)),
          ),
          children: [
            if (record.activity != null) _detailRow('What you were doing', record.activity!),
            if (action != null) _detailRow('What you tried', action),
            if (followup != null) _detailRow('Five-minute follow-up', followup),
            _detailRow('Trigger source', _sourceLabel(record.riskSource)),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard() => _card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              const Icon(Icons.history_toggle_off_rounded, size: 34, color: Color(0xFF8B8FA3)),
              const SizedBox(height: 8),
              Text(
                'No check-in records in the last 30 days.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF75798C)),
              ),
            ],
          ),
        ),
      );

  Widget _statChip(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F1FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$value $label',
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF625B82),
          ),
        ),
      );

  Widget _insightRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Icon(Icons.circle, size: 6, color: Color(0xFF2D9C79)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(fontSize: 11, height: 1.4, color: const Color(0xFF676B80)),
                  children: [
                    TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: GoogleFonts.poppins(fontSize: 10.5, color: const Color(0xFF8B8FA3)),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: GoogleFonts.poppins(fontSize: 10.8, fontWeight: FontWeight.w500, color: const Color(0xFF4F5368)),
              ),
            ),
          ],
        ),
      );

  Widget _disclaimer() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'Check-ins are your own reports and should be interpreted together with clinical assessment. They do not confirm a diagnosis, and an Aura alert by itself does not mean an anxiety episode occurred.',
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            height: 1.45,
            color: const Color(0xFF795B26),
          ),
        ),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE9E7F2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final amPm = local.hour < 12 ? 'AM' : 'PM';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} · $hour:$minute $amPm';
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'physiological_forecast':
        return 'Physiological forecast check-in';
      case 'physiological':
        return 'Physiological change check-in';
      default:
        return 'Aura check-in';
    }
  }
}
