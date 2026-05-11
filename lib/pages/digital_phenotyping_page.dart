import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../profile_page.dart';
import '../services/rating_settings.dart';

// ─────────────────────────────────────────────
// COLOUR TOKENS — deep forest-green forward theme
// ─────────────────────────────────────────────
class _C {
  // Backgrounds
  static const scaffold   = Color(0xFFF0FBF6); // soft mint-green scaffold
  static const cardBase   = Color(0xFFFFFFFF); // white cards
  static const cardGlass  = Color(0xFF0D3D26); // dark forest green for cluster card
  static const chip       = Color(0xFFEDFAF5); // green-tinted icon chip

  // Green scale
  static const g900 = Color(0xFF0A2218);
  static const g800 = Color(0xFF0D3D26);
  static const g700 = Color(0xFF115C35);
  static const g600 = Color(0xFF157A44);
  static const g500 = Color(0xFF1A9E6E); // main emerald accent
  static const g400 = Color(0xFF22C78A); // bright teal-green
  static const g300 = Color(0xFF5DDBA9);
  static const g200 = Color(0xFFA8F0D5);
  static const g100 = Color(0xFFD6FAF0);
  static const g50  = Color(0xFFEDFAF5);

  // Accent palette
  static const primary    = Color(0xFF1A9E6E); // emerald green (main)
  static const teal       = Color(0xFF0DBF8A); // bright teal
  static const amber      = Color(0xFFF59B24); // warm amber (risk)
  static const amberLight = Color(0xFFFEF3DC); // amber fill
  static const rose       = Color(0xFFEF5777); // high risk red-rose
  static const roseLight  = Color(0xFFFDEAEE); // rose fill
  static const cyan       = Color(0xFF00B4D8); // mood line cyan

  // Text
  static const textPrimary   = Color(0xFF0A2218); // deep forest
  static const textSecondary = Color(0xFF2D6B4F); // muted green-slate
  static const textMuted     = Color(0xFF6B9E85); // dim green-grey

  // Risk tier
  static const riskHigh = Color(0xFFEF5777);
  static const riskMid  = Color(0xFFF59B24);
  static const riskLow  = Color(0xFF1A9E6E);

  // Border
  static const border = Color(0xFFC8EFE0); // green-tinted border
}

// ─────────────────────────────────────────────
// PHENOTYPE DEFINITIONS
// ─────────────────────────────────────────────
const Map<int, Map<String, String>> kPhenotypes = {
  0: {'name': 'Social-Spatial\nWithdrawal',  'badge': 'Cluster A'},
  1: {'name': 'Circadian\nDisruption',        'badge': 'Cluster B'},
  2: {'name': 'Hypervigilant\nMobility',      'badge': 'Cluster C'},
};

class DigitalPhenotypingPage extends StatefulWidget {
  final String? userId;
  const DigitalPhenotypingPage({super.key, this.userId});

  @override
  State<DigitalPhenotypingPage> createState() => _DigitalPhenotypingPageState();
}

class _DigitalPhenotypingPageState extends State<DigitalPhenotypingPage> {
  Timer? _timer;
  final Random _rng = Random();

  List<FlSpot> _clinicalAnxiety  = [];
  List<FlSpot> _clinicalMood     = [];
  List<BarChartGroupData> _sociabilityData = [];
  List<FlSpot> _physicalActivity  = [];
  List<FlSpot> _digitalEngagement = [];

  int _timeStep = 7;

  // ── 24-hr risk curve (static per session from GATv2 output) ──
  final List<FlSpot> _riskCurveData = const [
    FlSpot(0,  0.20),
    FlSpot(4,  0.10),
    FlSpot(8,  0.40),
    FlSpot(12, 0.65),
    FlSpot(14, 0.85), // peak window
    FlSpot(16, 0.80),
    FlSpot(20, 0.55),
    FlSpot(23, 0.30),
  ];

  // ── Vulnerability score from GATv2 ──
  static const double _vulnerabilityScore = 0.72;

  // ── Phenotype cluster (0 = Social-Spatial Withdrawal) ──
  static const int _phenotypeCluster = 0;

  // ── Behavioural tags from attention weights ──
  static const List<Map<String, String>> _tags = [
    {'label': 'late nights at home',      'tier': 'high'},
    {'label': 'long solo study sessions', 'tier': 'mid'},
    {'label': 'frequent phone checking',  'tier': 'mid'},
  ];

  // ── Weekly risk levels (colour-coded, no raw numbers) ──
  static const List<Map<String, dynamic>> _weeklyRisk = [
    {'day': 'Mon', 'level': 0.22},
    {'day': 'Tue', 'level': 0.42},
    {'day': 'Wed', 'level': 0.20},
    {'day': 'Thu', 'level': 0.55},
    {'day': 'Fri', 'level': 0.75},
    {'day': 'Sat', 'level': 0.62},
    {'day': 'Sun', 'level': 0.48},
  ];

  // Mini spark bars shown on the risk score card.
  static const List<double> _riskSparkHeights = [18, 28, 16, 36, 42, 30, 24];

  @override
  void initState() {
    super.initState();
    _initializeData();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _updateLiveData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initializeData() {
    for (int i = 0; i < 7; i++) {
      _clinicalAnxiety.add(FlSpot(i.toDouble(), 2 + _rng.nextDouble() * 4));
      _clinicalMood.add(FlSpot(i.toDouble(), 3 + _rng.nextDouble() * 3));
      _sociabilityData.add(_buildSocBar(i));
      _physicalActivity.add(FlSpot(i.toDouble(), 20 + _rng.nextDouble() * 40));
      _digitalEngagement.add(FlSpot(i.toDouble(), 2  + _rng.nextDouble() * 6));
    }
  }

  BarChartGroupData _buildSocBar(int x, {double? toY}) => BarChartGroupData(
    x: x,
    barRods: [
      BarChartRodData(
        toY:   toY ?? (2 + _rng.nextDouble() * 12),
        color: _C.teal,
        width: 14,
        borderRadius: BorderRadius.circular(4),
      ),
    ],
  );

  void _updateLiveData() {
    if (!mounted) return;
    setState(() {
      _timeStep++;
      final x = _timeStep.toDouble();
      _clinicalAnxiety   = [..._clinicalAnxiety.sublist(1),   FlSpot(x, 2 + _rng.nextDouble() * 4)];
      _clinicalMood      = [..._clinicalMood.sublist(1),      FlSpot(x, 3 + _rng.nextDouble() * 3)];
      _physicalActivity  = [..._physicalActivity.sublist(1),  FlSpot(x, 20 + _rng.nextDouble() * 40)];
      _digitalEngagement = [..._digitalEngagement.sublist(1), FlSpot(x, 2  + _rng.nextDouble() * 6)];
      _sociabilityData   = [
        ..._sociabilityData.sublist(1),
        _buildSocBar(_timeStep),
      ];
    });
  }

  // ─── HELPERS ───────────────────────────────

  Color _riskColor(double score) =>
      score > 0.7 ? _C.riskHigh : (score > 0.4 ? _C.riskMid : _C.riskLow);

  String _riskLabel(double score) =>
      score > 0.7 ? 'High Risk' : (score > 0.4 ? 'Moderate Risk' : 'Low Risk');

  Color _riskBadgeBg(double score) => score > 0.7
      ? _C.roseLight
      : (score > 0.4 ? _C.amberLight : _C.g100);

  Color _weekBarColor(double level) => level > 0.65
      ? _C.riskHigh
      : (level > 0.45 ? _C.riskMid : _C.riskLow);

    Color _sparkColor(double height) => height >= 38
      ? _C.riskHigh
      : (height >= 26 ? _C.riskMid : _C.riskLow);

  Color _tagColor(String tier) =>
      tier == 'high' ? _C.roseLight : _C.amberLight;

  Color _tagTextColor(String tier) =>
      tier == 'high' ? _C.riskHigh : const Color(0xFF9A5E00);

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.scaffold,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Container(
        color: _C.scaffold,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 14),
                _buildNudgeBanner(),
                const SizedBox(height: 16),
                // Top row: score + cluster
                Row(children: [
                  Expanded(child: _buildVulnerabilityCard(_vulnerabilityScore)),
                  const SizedBox(width: 14),
                  Expanded(child: _buildClusterCard(_phenotypeCluster)),
                ]),
                const SizedBox(height: 18),
                _buildRiskCurveCard(),
                const SizedBox(height: 24),
                _buildSectionTitle('Data Collection Metrics', live: true),
                const SizedBox(height: 10),
                _buildMetricCard(
                  icon: Icons.screen_lock_portrait_rounded,
                  title: 'Screen State',
                  value: 'Unlocked 42 times',
                  subtitle: 'Average 4.2 hrs / day',
                ),
                const SizedBox(height: 10),
                _buildMetricCard(
                  icon: Icons.directions_walk_rounded,
                  title: 'Physical Activity',
                  value: 'Low Movement Detected',
                  subtitle: 'Based on accelerometer data',
                ),
                const SizedBox(height: 10),
                _buildMetricCard(
                  icon: Icons.location_on_rounded,
                  title: 'Location Cluster',
                  value: 'LOC_2 · Home zone',
                  subtitle: 'Stay-point via DBSCAN',
                ),
                const SizedBox(height: 10),
                _buildMetricCard(
                  icon: Icons.record_voice_over_rounded,
                  title: 'Social Interactions',
                  value: '3 conversations today',
                  subtitle: 'Speech detection · no recording',
                ),
                const SizedBox(height: 26),
                _buildSectionTitle('Live Subject Details', live: true),
                const SizedBox(height: 12),
                _buildChartCard(
                  title: 'Clinical Metrics (EMA)',
                  subtitle: 'Daily anxiety vs mood correlation',
                  icon: Icons.monitor_heart_rounded,
                  child: _buildClinicalLineChart(),
                ),
                const SizedBox(height: 14),
                _buildChartCard(
                  title: 'Sociability Index',
                  subtitle: 'Daily interactions (calls & SMS)',
                  icon: Icons.people_alt_rounded,
                  child: _buildSociabilityBarChart(),
                ),
                const SizedBox(height: 14),
                _buildChartCard(
                  title: 'Physical Activity',
                  subtitle: 'High motion events per day',
                  icon: Icons.fitness_center_rounded,
                  child: _buildPhysicalActivityAreaChart(),
                ),
                const SizedBox(height: 14),
                _buildChartCard(
                  title: 'Digital Engagement',
                  subtitle: 'Total screen time (hours)',
                  icon: Icons.phone_android_rounded,
                  child: _buildDigitalEngagementChart(),
                ),
                const SizedBox(height: 26),
                _buildSectionTitle('Weekly Trend'),
                const SizedBox(height: 12),
                _buildWeeklyTrendCard(),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── APP BAR ───────────────────────────────

  AppBar _buildAppBar() => AppBar(
    backgroundColor: _C.scaffold,
    elevation: 0,
    title: Text(
      'Digital Phenotyping',
      style: GoogleFonts.poppins(
        color: _C.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 17,
      ),
    ),
    actions: [
      _iconBtn(Icons.person_outline_rounded,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()))),
      _iconBtn(Icons.settings_rounded,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RatingSettingsPage()))),
      const SizedBox(width: 8),
    ],
  );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: IconButton(
      icon: Icon(icon, color: _C.textSecondary, size: 22),
      onPressed: onTap,
    ),
  );

  // ─── HEADER ────────────────────────────────

  Widget _buildHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Analysis Overview',
          style: GoogleFonts.poppins(
              fontSize: 24, fontWeight: FontWeight.w700,
              color: _C.textPrimary, letterSpacing: -0.5)),
      const SizedBox(height: 3),
      Text('Based on your recent digital interactions',
          style: GoogleFonts.poppins(fontSize: 13, color: _C.textMuted)),
    ],
  );

  // ─── NUDGE BANNER ──────────────────────────

  Widget _buildNudgeBanner() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _C.g50,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _C.g200),
      boxShadow: [BoxShadow(color: _C.g500.withOpacity(0.08),
          blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Row(
      children: [
        const Text('🌿', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Heads up — 2pm window approaching',
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _C.g700)),
              const SizedBox(height: 2),
              Text('Your graph shows afternoons tend to be harder. A short walk can help.',
                  style: GoogleFonts.poppins(fontSize: 11, color: _C.textSecondary)),
            ],
          ),
        ),
      ],
    ),
  );

  // ─── SECTION TITLE ─────────────────────────

  Widget _buildSectionTitle(String title, {bool live = false}) => Row(
    children: [
      Text(title,
          style: GoogleFonts.poppins(
              fontSize: 17, fontWeight: FontWeight.w700,
              color: _C.textPrimary, letterSpacing: -0.3)),
      if (live) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _C.g100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: _C.g400, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('LIVE',
                  style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: _C.g600)),
            ],
          ),
        ),
      ],
    ],
  );

  // ─── VULNERABILITY CARD ────────────────────

  Widget _buildVulnerabilityCard(double score) {
    final color   = _riskColor(score);
    final label   = _riskLabel(score);
    final badgeBg = _riskBadgeBg(score);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.cardBase,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.health_and_safety_rounded, color: _C.textMuted, size: 18),
            const SizedBox(width: 6),
            Text('Risk Score',
                style: GoogleFonts.poppins(fontSize: 12, color: _C.textMuted)),
          ]),
          const SizedBox(height: 12),
          Text(score.toStringAsFixed(2),
              style: GoogleFonts.poppins(
                  fontSize: 34, fontWeight: FontWeight.w700,
                  color: color, letterSpacing: -1)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: badgeBg, borderRadius: BorderRadius.circular(20)),
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _riskSparkHeights.map((h) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      height: h,
                      decoration: BoxDecoration(
                        color: _sparkColor(h).withOpacity(0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CLUSTER CARD ──────────────────────────

  Widget _buildClusterCard(int cluster) {
    final data = kPhenotypes[cluster] ?? kPhenotypes[0]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D3D26), Color(0xFF115C35), Color(0xFF157A44)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _C.g700),
        boxShadow: [BoxShadow(
            color: _C.g500.withOpacity(0.22),
            blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🌱', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text('Phenotype',
                style: GoogleFonts.poppins(fontSize: 12, color: _C.g300)),
          ]),
          const SizedBox(height: 12),
          Text(data['name']!,
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: Colors.white, height: 1.25, letterSpacing: -0.3)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Text(data['badge']!,
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w600, color: _C.g200)),
          ),
        ],
      ),
    );
  }

  // ─── 24-HR RISK CURVE ──────────────────────

  Widget _buildRiskCurveCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _C.cardBase,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _C.border),
      boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('24-Hour Risk Curve',
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w600,
                color: _C.textPrimary)),
        const SizedBox(height: 3),
        Text('Estimated anxiety risk based on your daily patterns',
            style: GoogleFonts.poppins(fontSize: 11, color: _C.textMuted)),
        const SizedBox(height: 20),
        SizedBox(
          height: 190,
          child: LineChart(LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: _C.border, strokeWidth: 1, dashArray: [5, 5]),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                      style: GoogleFonts.poppins(fontSize: 10, color: _C.textMuted)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 4,
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${v.toInt()}h',
                        style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: (v >= 12 && v <= 16)
                                ? _C.amber
                                : _C.textMuted,
                            fontWeight: (v >= 12 && v <= 16)
                                ? FontWeight.w600
                                : FontWeight.w400)),
                  ),
                ),
              ),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minX: 0, maxX: 23,
            minY: 0, maxY: 1.0,
            lineBarsData: [
              LineChartBarData(
                spots: _riskCurveData,
                isCurved: true,
                color: _C.amber,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                    radius: spot.y > 0.7 ? 5 : 3,
                    color: spot.y > 0.7 ? _C.amber : Colors.transparent,
                    strokeColor: spot.y > 0.7 ? _C.amber : Colors.transparent,
                    strokeWidth: 2,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: _C.amber.withOpacity(0.12),
                ),
              ),
            ],
          )),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _hourLabel('6am'),
            _hourLabel('10am'),
            _hourLabel('2pm ▲', peak: true),
            _hourLabel('4pm', peak: true),
            _hourLabel('8pm'),
            _hourLabel('12am'),
          ],
        ),
        const SizedBox(height: 14),
        // Behavioural tags from attention weights
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _tags.map((t) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _tagColor(t['tier']!),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(t['label']!,
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w500,
                    color: _tagTextColor(t['tier']!))),
          )).toList(),
        ),
        const SizedBox(height: 8),
        Text('from GATv2 attention weights',
            style: GoogleFonts.poppins(fontSize: 10, color: _C.textMuted)),
      ],
    ),
  );

  // ─── METRIC CARD ───────────────────────────

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _C.cardBase,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                  color: _C.chip, shape: BoxShape.circle,
                  border: Border.all(color: _C.border)),
              child: Icon(icon, color: _C.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w500,
                          color: _C.textMuted)),
                  const SizedBox(height: 3),
                  Text(value,
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: _C.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: _C.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _C.border, size: 22),
          ],
        ),
      );

  // ─── WEEKLY TREND CARD ─────────────────────

  Widget _buildWeeklyTrendCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _C.cardBase,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _C.border),
      boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('7-Day Vulnerability',
            style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: _C.textPrimary)),
        const SizedBox(height: 3),
        Text('Colour intensity = risk level · no raw numbers shown',
            style: GoogleFonts.poppins(fontSize: 11, color: _C.textMuted)),
        const SizedBox(height: 16),
        // Bar chart
        SizedBox(
          height: 70,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _weeklyRisk.map((d) {
              final pct = (d['level'] as double);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: pct,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _weekBarColor(pct),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: _weeklyRisk.map((d) => Expanded(
            child: Text(d['day'] as String,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 10, color: _C.textMuted)),
          )).toList(),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _C.amberLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('⚠  3 higher-risk evenings in a row — Fri through Sun',
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w500,
                  color: const Color(0xFF854F0B))),
        ),
      ],
    ),
  );

  Widget _hourLabel(String label, {bool peak = false}) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 10,
        color: peak ? _C.amber : _C.textMuted,
        fontWeight: peak ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  // ─── CHART CARD WRAPPER ────────────────────

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _C.cardBase,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                    color: _C.g400, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Icon(icon, color: _C.primary, size: 20),
              const SizedBox(width: 6),
              Text(title,
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: _C.textPrimary)),
            ]),
            const SizedBox(height: 3),
            Text(subtitle,
                style: GoogleFonts.poppins(fontSize: 11, color: _C.textMuted)),
            const SizedBox(height: 20),
            SizedBox(height: 160, child: child),
          ],
        ),
      );

  // ─── LIVE CHARTS ───────────────────────────

  FlGridData get _gridData => FlGridData(
    show: true,
    drawVerticalLine: false,
    getDrawingHorizontalLine: (_) =>
        FlLine(color: _C.border, strokeWidth: 1, dashArray: [5, 5]),
  );

  FlTitlesData get _minimalTitles => FlTitlesData(
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 28,
        getTitlesWidget: (v, _) => Text(v.toInt().toString(),
            style: GoogleFonts.poppins(fontSize: 10, color: _C.textMuted)),
      ),
    ),
    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );

  Widget _buildClinicalLineChart() => LineChart(LineChartData(
    gridData: _gridData,
    titlesData: _minimalTitles,
    borderData: FlBorderData(show: false),
    minY: 0, maxY: 8,
    lineBarsData: [
      LineChartBarData(
        spots: _clinicalAnxiety,
        isCurved: true,
        color: _C.rose,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: _C.rose.withOpacity(0.08)),
      ),
      LineChartBarData(
        spots: _clinicalMood,
        isCurved: true,
        color: _C.cyan,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
      ),
    ],
  ));

  Widget _buildSociabilityBarChart() => BarChart(BarChartData(
    gridData: _gridData,
    titlesData: _minimalTitles,
    borderData: FlBorderData(show: false),
    maxY: 16,
    barGroups: _sociabilityData.map((g) => BarChartGroupData(
      x: g.x,
      barRods: g.barRods.map((r) => r.copyWith(color: _C.teal)).toList(),
    )).toList(),
  ));

  Widget _buildPhysicalActivityAreaChart() => LineChart(LineChartData(
    gridData: _gridData,
    titlesData: _minimalTitles,
    borderData: FlBorderData(show: false),
    minY: 0, maxY: 60,
    lineBarsData: [
      LineChartBarData(
        spots: _physicalActivity,
        isCurved: true,
        color: _C.g400,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: _C.g400.withOpacity(0.10)),
      ),
    ],
  ));

  Widget _buildDigitalEngagementChart() => LineChart(LineChartData(
    gridData: _gridData,
    titlesData: _minimalTitles,
    borderData: FlBorderData(show: false),
    minY: 0, maxY: 8,
    lineBarsData: [
      LineChartBarData(
        spots: _digitalEngagement,
        isCurved: true,
        color: _C.primary,
        barWidth: 2.5,
        dotData: FlDotData(
          show: true,
          getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
            radius: 3,
            color: _C.primary,
            strokeColor: _C.g100,
            strokeWidth: 1.5,
          ),
        ),
      ),
    ],
  ));
}