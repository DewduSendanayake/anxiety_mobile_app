import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../profile_page.dart';
import '../services/rating_settings.dart';

// ─────────────────────────────────────────────
// COLOUR TOKENS  — light theme  (green-forward)
// ─────────────────────────────────────────────
class _C {
  // Backgrounds
  static const scaffold   = Color(0xFFF0F7F4); // very soft mint-green tint
  static const cardBase   = Color(0xFFFFFFFF); // pure white cards
  static const cardGlass  = Color(0xFFF2FAF6); // light green tint for cluster card
  static const chip       = Color(0xFFE6F5EE); // green-tinted icon chip background

  // Accent palette
  static const primary    = Color(0xFF1A9E6E); // rich emerald-green (main accent)
  static const teal       = Color(0xFF0DBF8A); // brighter teal-green
  static const amber      = Color(0xFFF59B24); // warm amber
  static const rose       = Color(0xFFEF5777); // rose
  static const cyan       = Color(0xFF00B4D8); // cyan
  static const greenLight = Color(0xFFD1FAE5); // soft green for badge fills

  // Text
  static const textPrimary   = Color(0xFF1A2D40);
  static const textSecondary = Color(0xFF4A7566); // muted green-slate
  static const textMuted     = Color(0xFF8AADA0); // dim green-grey

  // Risk tier colours
  static const riskHigh   = Color(0xFFE53E3E);
  static const riskMid    = Color(0xFFED8936);
  static const riskLow    = Color(0xFF1A9E6E);

  // Divider / border
  static const border = Color(0xFFD6EDE4); // green-tinted border
}

class DigitalPhenotypingPage extends StatefulWidget {
  final String? userId;
  const DigitalPhenotypingPage({super.key, this.userId});

  @override
  State<DigitalPhenotypingPage> createState() => _DigitalPhenotypingPageState();
}

class _DigitalPhenotypingPageState extends State<DigitalPhenotypingPage> {
  Timer? _timer;
  final Random _rng = Random();

  List<FlSpot> _clinicalAnxiety = [];
  List<FlSpot> _clinicalMood = [];
  List<BarChartGroupData> _sociabilityData = [];
  List<FlSpot> _physicalActivity = [];
  List<FlSpot> _digitalEngagement = [];

  int _timeStep = 7;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _updateLiveData();
    });
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

      _sociabilityData.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: 2 + _rng.nextDouble() * 12,
              color: _C.primary,
              width: 14,
              borderRadius: BorderRadius.circular(4),
            )
          ],
        ),
      );

      _physicalActivity.add(FlSpot(i.toDouble(), 20 + _rng.nextDouble() * 40));
      _digitalEngagement.add(FlSpot(i.toDouble(), 2 + _rng.nextDouble() * 6));
    }
  }

  void _updateLiveData() {
    if (!mounted) return;
    setState(() {
      _timeStep++;
      double newX = _timeStep.toDouble();

      _clinicalAnxiety.removeAt(0);
      _clinicalMood.removeAt(0);
      _sociabilityData.removeAt(0);
      _physicalActivity.removeAt(0);
      _digitalEngagement.removeAt(0);

      _clinicalAnxiety.add(FlSpot(newX, 2 + _rng.nextDouble() * 4));
      _clinicalMood.add(FlSpot(newX, 3 + _rng.nextDouble() * 3));

      _sociabilityData.add(
        BarChartGroupData(
          x: _timeStep,
          barRods: [
            BarChartRodData(
              toY: 2 + _rng.nextDouble() * 12,
              color: _C.primary,
              width: 14,
              borderRadius: BorderRadius.circular(4),
            )
          ],
        ),
      );

      _physicalActivity.add(FlSpot(newX, 20 + _rng.nextDouble() * 40));
      _digitalEngagement.add(FlSpot(newX, 2 + _rng.nextDouble() * 6));
    });
  }

  @override
  Widget build(BuildContext context) {
    const double vulnerabilityScore = 0.72;
    const int phenotypeCluster = 1;

    final List<FlSpot> riskCurveData = [
      const FlSpot(0, 0.2),
      const FlSpot(4, 0.1),
      const FlSpot(8, 0.4),
      const FlSpot(12, 0.7),
      const FlSpot(16, 0.85),
      const FlSpot(20, 0.6),
      const FlSpot(23, 0.3),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      // ── BACKGROUND: soft blue-grey ──
      backgroundColor: _C.scaffold,
      appBar: AppBar(
        backgroundColor: _C.scaffold,
        elevation: 0,
        title: Text(
          'Digital Phenotyping',
          style: GoogleFonts.poppins(
            color: _C.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded, color: _C.textSecondary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: _C.textSecondary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RatingSettingsPage()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
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
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _buildVulnerabilityCard(vulnerabilityScore)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildClusterCard(phenotypeCluster)),
                  ],
                ),
                const SizedBox(height: 20),
                _buildRiskCurveCard(riskCurveData),
                const SizedBox(height: 30),
                Text(
                  "Live Subject Details",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _C.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 20),
                _buildRiskCurveCard(riskCurveData),
                const SizedBox(height: 30),
                Text(
                  "Data Collection Metrics",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _C.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildMetricCard(
                  icon: Icons.screen_lock_portrait_rounded,
                  title: "Screen State",
                  value: "Unlocked 42 times",
                  subtitle: "Average 4.2 hrs/day",
                ),
                const SizedBox(height: 12),
                _buildMetricCard(
                  icon: Icons.directions_walk_rounded,
                  title: "Physical Activity",
                  value: "Low Movement Detected",
                  subtitle: "Based on accelerometer data",
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── ORIGINAL WIDGETS (colours swapped, structure untouched) ───

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Analysis Overview",
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: _C.textPrimary,            // ← was AppTheme.kTextDark
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Based on your recent digital interactions",
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: _C.textSecondary,          // ← was kTextDark.withOpacity(0.7)
          ),
        ),
      ],
    );
  }

  Widget _buildVulnerabilityCard(double score) {
    final Color scoreColor = score > 0.7
        ? _C.riskHigh
        : (score > 0.4 ? _C.riskMid : _C.riskLow);
    final String riskLabel = score > 0.7
        ? "High Risk"
        : (score > 0.4 ? "Moderate Risk" : "Low Risk");
    final Color badgeBg = score > 0.7
        ? const Color(0xFFFFEBEB)
        : (score > 0.4 ? const Color(0xFFFFF3E0) : _C.greenLight);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.cardBase,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_rounded, color: _C.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text(
                "Risk Score",
                style: GoogleFonts.poppins(fontSize: 14, color: _C.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            score.toStringAsFixed(2),
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: scoreColor,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              riskLabel,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scoreColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClusterCard(int cluster) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.cardGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.primary.withOpacity(0.30), width: 1),
        boxShadow: [
          BoxShadow(
            color: _C.primary.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_work_rounded, color: _C.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                "Phenotype",
                style: GoogleFonts.poppins(fontSize: 14, color: _C.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Social-Spatial\nWithdrawal",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _C.primary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _C.greenLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "Cluster ${cluster == 1 ? 'A' : 'B'}",
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _C.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskCurveCard(List<FlSpot> spots) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.cardBase,                   // ← was Colors.white
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "24-Hour Risk Curve",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _C.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Estimated anxiety risk based on daily patterns",
            style: GoogleFonts.poppins(fontSize: 12, color: _C.textSecondary),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: _C.border,
                    strokeWidth: 1,
                    dashArray: [5, 5],
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(1),
                        style: GoogleFonts.poppins(fontSize: 10, color: _C.textMuted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 4,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          "${value.toInt()}h",
                          style: GoogleFonts.poppins(fontSize: 10, color: _C.textMuted),
                        ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 23,
                minY: 0,
                maxY: 1.0,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: _C.amber,           // ← was purple; amber = risk feel
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _C.amber.withOpacity(0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.cardBase,                   // ← was Colors.white
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _C.chip,                 // ← was 0xFFF5F3FF (lavender-white)
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _C.primary, size: 24),   // ← was purple
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _C.textSecondary)),
                const SizedBox(height: 4),
                Text(value,
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _C.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.poppins(fontSize: 12, color: _C.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── LIVE CHARTS ───

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.cardBase,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _C.primary, size: 22),         // ← was purple
              const SizedBox(width: 8),
              Text(title,
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _C.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle,
              style: GoogleFonts.poppins(fontSize: 12, color: _C.textSecondary)),
          const SizedBox(height: 24),
          SizedBox(height: 180, child: child),
        ],
      ),
    );
  }

  Widget _buildClinicalLineChart() {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: _C.border, strokeWidth: 1, dashArray: [5, 5]),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString(),
                  style: TextStyle(color: _C.textMuted, fontSize: 10)),
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: 8,
        lineBarsData: [
          LineChartBarData(
            spots: _clinicalAnxiety,
            isCurved: true,
            color: _C.rose,                   // ← was Colors.pinkAccent (kept similar, just token)
            barWidth: 3,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: _clinicalMood,
            isCurved: true,
            color: _C.cyan,                   // ← was Colors.cyanAccent (kept similar, just token)
            barWidth: 3,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  Widget _buildSociabilityBarChart() {
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: _C.border, strokeWidth: 1, dashArray: [5, 5]),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString(),
                  style: TextStyle(color: _C.textMuted, fontSize: 10)),
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        maxY: 16,
        barGroups: _sociabilityData.map((group) {
          return BarChartGroupData(
            x: group.x,
            barRods: group.barRods.map((rod) {
              return rod.copyWith(color: _C.teal);  // ← was purple; teal = social/positive
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPhysicalActivityAreaChart() {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: _C.border, strokeWidth: 1, dashArray: [5, 5]),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString(),
                  style: TextStyle(color: _C.textMuted, fontSize: 10)),
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: 60,
        lineBarsData: [
          LineChartBarData(
            spots: _physicalActivity,
            isCurved: true,
            color: _C.teal,                   // ← was purple; teal = health/activity
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: _C.teal.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDigitalEngagementChart() {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: _C.border, strokeWidth: 1, dashArray: [5, 5]),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString(),
                  style: TextStyle(color: _C.textMuted, fontSize: 10)),
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: 8,
        lineBarsData: [
          LineChartBarData(
            spots: _digitalEngagement,
            isCurved: true,
            color: _C.primary,                // ← was purple; sky-blue = screen/digital
            barWidth: 3,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}