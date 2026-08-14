// ─────────────────────────────────────────────────────────────────────────────
//  Component 2 — Behavioural Observation Panel
//
//  REPLACES the previous risk-score page. Every value shown here is either a
//  real measurement from the collection service or an explicit "not available"
//  state. Nothing is simulated.
//
//  WHY THE RISK SCORE WAS REMOVED
//  Validation on GLOBEM (705 participants, four cohorts, anxiety subscale):
//      AUROC 0.548 [95% CI 0.516-0.588], permutation null 0.487
//      Brier 0.254 vs 0.189 for a constant predictor
//      PPV 0.262 vs prevalence 0.253            (lift +0.010)
//      Decision curve net benefit 0.0006        (~0.6 cases per 1,000)
//      Cross-cohort transfer AUROC 0.478        (no generalisation)
//  A model that does not transfer between two cohorts at the same university
//  two years apart cannot be transferred to this study population.
//
//  WHAT REPLACES IT
//  Descriptive behavioural observations relative to each participant's own
//  baseline, plus honest data-quality reporting. No predictive claim is made,
//  so no predictive claim can fail.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:call_log/call_log.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/background_service_helper.dart';

// ─────────────────────────────────────────────
// COLOUR TOKENS — unchanged from the previous page
// ─────────────────────────────────────────────
class _C {
  static const scaffold = Color(0xFFF5F3FF);
  static const cardBase = Color(0xFFFFFFFF);
  static const chip     = Color(0xFFF0ECFF);

  static const p500 = Color(0xFF5E60CE);
  static const p400 = Color(0xFF7C5CBF);
  static const p200 = Color(0xFFC4B5FD);
  static const p100 = Color(0xFFF0ECFF);

  static const primary  = Color(0xFF5E60CE);
  static const amber    = Color(0xFFF59B24);
  static const amberBg  = Color(0xFFFEF3DC);
  static const rose     = Color(0xFFEF5777);
  static const roseBg   = Color(0xFFFDEAEE);
  static const teal     = Color(0xFF0F9D8C);
  static const tealBg   = Color(0xFFE3F5F2);

  static const textPrimary   = Color(0xFF2D3142);
  static const textSecondary = Color(0xFF5A607F);
  static const textMuted     = Color(0xFF9095A7);
  static const border        = Color(0xFFE8E5F4);
}

// ─────────────────────────────────────────────
// DATA MODEL — mirrors component2_output.py exactly
// ─────────────────────────────────────────────

/// A single behavioural observation expressed against the participant's own
/// baseline. [z] is null when no baseline exists yet.
class Observation {
  final String key;
  final String label;
  final double? z;
  final String direction;   // above | below | stable | no_baseline | unknown
  final String confidence;  // high | medium | low | insufficient
  final double? value;
  final String unit;

  const Observation({
    required this.key,
    required this.label,
    required this.z,
    required this.direction,
    required this.confidence,
    this.value,
    this.unit = '',
  });

  factory Observation.fromJson(String key, Map<String, dynamic> j) => Observation(
        key: key,
        label: j['label'] as String? ?? key,
        z: (j['z'] as num?)?.toDouble(),
        direction: j['direction'] as String? ?? 'unknown',
        confidence: j['confidence'] as String? ?? 'low',
        value: (j['value'] as num?)?.toDouble(),
        unit: j['unit'] as String? ?? '',
      );

  bool get isFlagged => z != null && z!.abs() >= 1.5;
}

class ObservationPayload {
  final String participantId;
  final DateTime windowStart;
  final DateTime windowEnd;
  final bool baselineReady;
  final bool reportable;
  final List<Observation> observations;
  final List<String> blockingIssues;
  final int daysWithData;
  final int baselineDaysAvailable;
  final int baselineDaysRequired;
  final int emaReceived;
  final int emaExpected;

  const ObservationPayload({
    required this.participantId,
    required this.windowStart,
    required this.windowEnd,
    required this.baselineReady,
    required this.reportable,
    required this.observations,
    required this.blockingIssues,
    required this.daysWithData,
    required this.baselineDaysAvailable,
    required this.baselineDaysRequired,
    required this.emaReceived,
    required this.emaExpected,
  });

  factory ObservationPayload.fromJson(Map<String, dynamic> j) {
    final obsMap = (j['observations'] as Map<String, dynamic>? ?? {});
    final q = (j['data_quality'] as Map<String, dynamic>? ?? {});
    final w = (j['window'] as Map<String, dynamic>? ?? {});
    return ObservationPayload(
      participantId: j['participant_id'] as String? ?? 'unknown',
      windowStart: DateTime.tryParse(w['start'] as String? ?? '') ?? DateTime.now(),
      windowEnd: DateTime.tryParse(w['end'] as String? ?? '') ?? DateTime.now(),
      baselineReady: j['baseline_ready'] as bool? ?? false,
      reportable: j['reportable'] as bool? ?? false,
      observations: obsMap.entries
          .map((e) => Observation.fromJson(e.key, e.value as Map<String, dynamic>))
          .toList(),
      blockingIssues:
          (j['blocking_issues'] as List?)?.map((e) => e.toString()).toList() ?? [],
      daysWithData: (q['days_with_data'] as num?)?.toInt() ?? 0,
      baselineDaysAvailable: (q['baseline_days_available'] as num?)?.toInt() ?? 0,
      baselineDaysRequired: (q['baseline_days_required'] as num?)?.toInt() ?? 28,
      emaReceived: (q['ema_received'] as num?)?.toInt() ?? 0,
      emaExpected: (q['ema_expected'] as num?)?.toInt() ?? 0,
    );
  }

  /// Local fallback used until the analysis backend is wired up. Reports the
  /// baseline-building state honestly rather than inventing observations.
  factory ObservationPayload.buildingBaseline({
    required String participantId,
    required int daysEnrolled,
    required int emaReceived,
    required int emaExpected,
  }) {
    const required = 28;
    return ObservationPayload(
      participantId: participantId,
      windowStart: DateTime.now().subtract(const Duration(days: 27)),
      windowEnd: DateTime.now(),
      baselineReady: daysEnrolled >= required * 2,
      reportable: false,
      observations: const [],
      blockingIssues: [
        'Personal baseline requires $required days of data before the '
            'reporting window. $daysEnrolled days collected so far.',
      ],
      daysWithData: daysEnrolled.clamp(0, 28),
      baselineDaysAvailable: (daysEnrolled - 28).clamp(0, 999),
      baselineDaysRequired: required,
      emaReceived: emaReceived,
      emaExpected: emaExpected,
    );
  }
}

// ─────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────
class DigitalPhenotypingPage extends StatefulWidget {
  final String? userId;
  const DigitalPhenotypingPage({super.key, this.userId});

  @override
  State<DigitalPhenotypingPage> createState() => _DigitalPhenotypingPageState();
}

class _DigitalPhenotypingPageState extends State<DigitalPhenotypingPage> {
  bool _loading = true;

  // Real device measurements
  int _callCount = 0;
  int _smsCount = 0;
  double _screenHours = 0.0;
  String _locationStatus = 'Checking…';
  double? _locationAccuracy;
  String _batteryStatus = 'Checking…';
  int _queueSize = 0;
  bool _serviceRunning = false;
  int _daysEnrolled = 0;

  ObservationPayload? _payload;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([_fetchDeviceMetrics(), _fetchServiceStatus()]);
    await _fetchObservations();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchServiceStatus() async {
    try {
      _queueSize = await BackgroundServiceHelper.getOfflineQueueSize();
      _serviceRunning = await BackgroundServiceHelper.isServiceRunning();
      final prefs = await SharedPreferences.getInstance();
      final enrolled = prefs.getString('enrolled_date');
      if (enrolled != null) {
        final d = DateTime.tryParse(enrolled);
        if (d != null) _daysEnrolled = DateTime.now().difference(d).inDays;
      }
    } catch (e) {
      debugPrint('Service status error: $e');
    }
  }

  /// Loads the observation payload. Until the analysis backend is available
  /// this reports the baseline-building state — it never fabricates values.
  Future<void> _fetchObservations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('c2_observation_payload');
      if (cached != null && cached.isNotEmpty) {
        _payload = ObservationPayload.fromJson(
            jsonDecode(cached) as Map<String, dynamic>);
        return;
      }
    } catch (e) {
      debugPrint('Observation payload parse error: $e');
    }
    _payload = ObservationPayload.buildingBaseline(
      participantId: widget.userId ?? await BackgroundServiceHelper.getCachedId(),
      daysEnrolled: _daysEnrolled,
      emaReceived: 0,
      emaExpected: 0,
    );
  }

  Future<void> _fetchDeviceMetrics() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final entries = await CallLog.query(dateFrom: now - 86400000)
          .timeout(const Duration(seconds: 5), onTimeout: () => []);
      _callCount = entries.length;

      final smsQuery = SmsQuery();
      final inbox = await smsQuery
          .querySms(kinds: [SmsQueryKind.inbox])
          .timeout(const Duration(seconds: 5), onTimeout: () => []);
      final sent = await smsQuery
          .querySms(kinds: [SmsQueryKind.sent])
          .timeout(const Duration(seconds: 5), onTimeout: () => []);
      bool isToday(DateTime? d) {
        if (d == null) return false;
        final n = DateTime.now();
        return d.year == n.year && d.month == n.month && d.day == n.day;
      }

      _smsCount = inbox.where((m) => isToday(m.date)).length +
          sent.where((m) => isToday(m.date)).length;

      final end = DateTime.now();
      final start = DateTime(end.year, end.month, end.day);
      final usage = await UsageStats.queryUsageStats(start, end)
          .timeout(const Duration(seconds: 5), onTimeout: () => []);
      double secs = 0;
      for (final u in usage) {
        secs += (int.tryParse(u.totalTimeInForeground ?? '0') ?? 0) / 1000;
      }
      _screenHours = secs / 3600;

      final battery = Battery();
      final level = await battery.batteryLevel
          .timeout(const Duration(seconds: 3), onTimeout: () => 0);
      final state = await battery.batteryState
          .timeout(const Duration(seconds: 3), onTimeout: () => BatteryState.unknown);
      _batteryStatus = '$level% · ${state.name}';

      try {
        // NOTE: high accuracy, matching background_service.dart. The pipeline
        // requires <100 m fixes; LocationAccuracy.low returns 100-300 m.
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 8));
        _locationAccuracy = pos.accuracy;
        _locationStatus = pos.accuracy <= 100
            ? 'Active · ±${pos.accuracy.toStringAsFixed(0)} m'
            : 'Low precision · ±${pos.accuracy.toStringAsFixed(0)} m';
      } catch (_) {
        _locationStatus = 'Unavailable — check permissions';
      }
    } catch (e) {
      debugPrint('Device metrics error: $e');
    }
  }

  // ─── HELPERS ─────────────────────────────────

  Color _zColor(double? z) {
    if (z == null) return _C.textMuted;
    final a = z.abs();
    if (a >= 2.0) return _C.rose;
    if (a >= 1.5) return _C.amber;
    return _C.teal;
  }

  Color _zBg(double? z) {
    if (z == null) return _C.p100;
    final a = z.abs();
    if (a >= 2.0) return _C.roseBg;
    if (a >= 1.5) return _C.amberBg;
    return _C.tealBg;
  }

  IconData _dirIcon(String d) => switch (d) {
        'above' => Icons.trending_up_rounded,
        'below' => Icons.trending_down_rounded,
        'stable' => Icons.trending_flat_rounded,
        _ => Icons.remove_rounded,
      };

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.scaffold,
      appBar: AppBar(
        backgroundColor: _C.scaffold,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: _C.textPrimary, size: 20),
                onPressed: () => Navigator.pop(context))
            : null,
        title: Text('Behavioural Context',
            style: GoogleFonts.poppins(
                color: _C.textPrimary, fontWeight: FontWeight.w600, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _C.textMuted, size: 20),
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _C.primary))
            : RefreshIndicator(
                onRefresh: _load,
                color: _C.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(),
                      const SizedBox(height: 16),
                      _observationCard(),
                      const SizedBox(height: 18),
                      _sectionTitle('Collection Status'),
                      const SizedBox(height: 10),
                      _collectionStatusCard(),
                      const SizedBox(height: 18),
                      _sectionTitle('Today\u2019s Measurements'),
                      const SizedBox(height: 10),
                      _metric(Icons.location_on_rounded, 'Location',
                          _locationStatus,
                          'GPS fix every 15 minutes',
                          warn: _locationAccuracy != null && _locationAccuracy! > 100),
                      const SizedBox(height: 10),
                      _metric(Icons.screen_lock_portrait_rounded, 'Screen time',
                          '${_screenHours.toStringAsFixed(1)} hrs',
                          'Foreground app usage since midnight'),
                      const SizedBox(height: 10),
                      _metric(Icons.record_voice_over_rounded, 'Communication',
                          '$_callCount calls · $_smsCount SMS',
                          'Counts only — no content is collected'),
                      const SizedBox(height: 10),
                      _metric(Icons.battery_charging_full_rounded, 'Battery',
                          _batteryStatus, 'Affects collection reliability'),
                      const SizedBox(height: 18),
                      _disclaimerCard(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ─── HEADER ──────────────────────────────────

  Widget _header() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Behavioural observations',
              style: GoogleFonts.poppins(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: _C.textPrimary,
                  letterSpacing: -0.5)),
          const SizedBox(height: 3),
          Text('Measured against your own typical patterns',
              style: GoogleFonts.poppins(fontSize: 13, color: _C.textMuted)),
        ],
      );

  Widget _sectionTitle(String t) => Text(t,
      style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: _C.textPrimary,
          letterSpacing: -0.3));

  // ─── OBSERVATION CARD ────────────────────────

  Widget _observationCard() {
    final p = _payload;
    if (p == null) return const SizedBox.shrink();

    if (!p.reportable) return _baselineBuildingCard(p);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _C.cardBase,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _C.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.insights_rounded, color: _C.primary, size: 19),
            const SizedBox(width: 8),
            Text('Last 28 days',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _C.textPrimary)),
          ]),
          const SizedBox(height: 4),
          Text('Compared with your own baseline',
              style: GoogleFonts.poppins(fontSize: 11, color: _C.textMuted)),
          const SizedBox(height: 16),
          ...p.observations.map(_observationRow),
        ],
      ),
    );
  }

  Widget _observationRow(Observation o) {
    final hasZ = o.z != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: _zBg(o.z), borderRadius: BorderRadius.circular(10)),
            child: Icon(_dirIcon(o.direction), size: 18, color: _zColor(o.z)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.label,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _C.textPrimary)),
                Text(
                    hasZ
                        ? '${o.direction == 'stable' ? 'Within' : 'Outside'} your usual range'
                        : 'Not enough data yet',
                    style:
                        GoogleFonts.poppins(fontSize: 11, color: _C.textMuted)),
              ],
            ),
          ),
          if (hasZ)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: _zBg(o.z), borderRadius: BorderRadius.circular(20)),
              child: Text('${o.z! >= 0 ? '+' : ''}${o.z!.toStringAsFixed(1)}σ',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _zColor(o.z))),
            )
          else
            Text('—',
                style: GoogleFonts.poppins(fontSize: 13, color: _C.textMuted)),
        ],
      ),
    );
  }

  Widget _baselineBuildingCard(ObservationPayload p) {
    final have = p.baselineDaysAvailable;
    final need = p.baselineDaysRequired;
    final frac = need == 0 ? 0.0 : (have / need).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _C.cardBase,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.hourglass_top_rounded, color: _C.p400, size: 19),
            const SizedBox(width: 8),
            Text('Building your baseline',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _C.textPrimary)),
          ]),
          const SizedBox(height: 6),
          Text(
              'Observations compare your recent behaviour with your own typical '
              'patterns. That needs $need days of history first.',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: _C.textSecondary, height: 1.45)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              backgroundColor: _C.p100,
              valueColor: const AlwaysStoppedAnimation(_C.p400),
            ),
          ),
          const SizedBox(height: 8),
          Text('Day $have of $need',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _C.p500)),
          if (p.blockingIssues.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...p.blockingIssues.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.info_outline_rounded,
                            size: 14, color: _C.textMuted),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(b,
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: _C.textMuted,
                                  height: 1.4))),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  // ─── COLLECTION STATUS ───────────────────────

  Widget _collectionStatusCard() {
    final ok = _serviceRunning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.cardBase,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        children: [
          Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: ok ? _C.teal : _C.rose, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Text(ok ? 'Collection active' : 'Collection stopped',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _C.textPrimary)),
            const Spacer(),
            Text('$_daysEnrolled days enrolled',
                style: GoogleFonts.poppins(fontSize: 11, color: _C.textMuted)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _statTile('Pending upload', '$_queueSize',
                    warn: _queueSize > 500)),
            const SizedBox(width: 10),
            Expanded(
                child: _statTile('Days with data',
                    '${_payload?.daysWithData ?? 0}/28')),
          ]),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, {bool warn = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
            color: warn ? _C.amberBg : _C.p100,
            borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: warn ? _C.amber : _C.p500)),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.poppins(fontSize: 11, color: _C.textMuted)),
          ],
        ),
      );

  // ─── METRIC ROW ──────────────────────────────

  Widget _metric(IconData icon, String title, String value, String subtitle,
          {bool warn = false}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _C.cardBase,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: warn ? _C.amber.withValues(alpha: 0.5) : _C.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: warn ? _C.amberBg : _C.chip, shape: BoxShape.circle),
              child: Icon(icon, color: warn ? _C.amber : _C.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: _C.textMuted)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _C.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: _C.textMuted)),
                ],
              ),
            ),
          ],
        ),
      );

  // ─── DISCLAIMER ──────────────────────────────

  Widget _disclaimerCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _C.p100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.p200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.shield_outlined, size: 17, color: _C.p500),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  'These are descriptive observations of your own behaviour over '
                  'time. They are not a diagnosis, a risk score, or a prediction. '
                  'Discuss any concerns with your clinician.',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: _C.textSecondary, height: 1.5)),
            ),
          ],
        ),
      );
}