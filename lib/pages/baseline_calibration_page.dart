import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/chest_strap_service.dart';
import 'main_navigation_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Baseline Calibration Page
//
// Collects 3 minutes of resting calibration data (3 x 60-second window readings)
// directly from the ChestStrap_V3 BLE device, then computes mean and standard
// deviation across the windows and uploads them to the /set_norm_params endpoint.
// ─────────────────────────────────────────────────────────────────────────────

class BaselineCalibrationPage extends StatefulWidget {
  final String userId;
  const BaselineCalibrationPage({super.key, required this.userId});

  @override
  State<BaselineCalibrationPage> createState() =>
      _BaselineCalibrationPageState();
}

class _BaselineCalibrationPageState extends State<BaselineCalibrationPage>
    with TickerProviderStateMixin {
  // ── Constants ──────────────────────────────────────────────────
  static const int _calibrationDurationSeconds = 180; // 3 minutes
  static const int _minimumReadings = 3; // minimum windows required for stats

  // ── State ──────────────────────────────────────────────────────
  _Phase _phase = _Phase.instructions;
  int _elapsedSeconds = 0;
  bool _uploading = false;
  String? _errorMessage;

  final List<ChestStrapReading> _collectedReadings = [];
  Timer? _collectionTimer;

  // Calibrated physiological features
  double _restingHR = 70.0;
  double _restingBR = 16.0;
  double _restingTemp = 36.6;

  // ── Animation ──────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _waveController;
  late Animation<double> _waveAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _waveAnimation = CurvedAnimation(
      parent: _waveController,
      curve: Curves.linear,
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _collectionTimer?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // Data Collection
  // ═══════════════════════════════════════════════════════════════

  void _startCalibration() {
    _collectedReadings.clear();

    // Safety check: is chest strap connected?
    if (!ChestStrapService().isConnected) {
      setState(() {
        _errorMessage = 'Chest strap is not connected. Please connect ChestStrap_V3 first.';
        _phase = _Phase.error;
      });
      return;
    }

    setState(() {
      _phase = _Phase.collecting;
      _elapsedSeconds = 0;
      _errorMessage = null;
    });

    // Listen to real chest strap data stream
    ChestStrapService().onDataReceived = (reading) {
      if (!mounted) return;
      
      setState(() {
        _collectedReadings.add(reading);
      });

    };

    // UI countdown and safety timeout timer
    _collectionTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() => _elapsedSeconds++);

        if (_elapsedSeconds >= _calibrationDurationSeconds &&
            _collectedReadings.length >= _minimumReadings) {
          timer.cancel();
          _finishCollection();
          return;
        }

        // Safety timeout: if after 4 minutes (240s) we still don't have enough readings
        if (_elapsedSeconds >= 240 && _collectedReadings.length < _minimumReadings) {
          timer.cancel();
          setState(() {
            _errorMessage = 'Not enough data received from chest strap after 4 minutes. Only got ${_collectedReadings.length} readings. Please ensure the strap is powered on and within range, then try again.';
            _phase = _Phase.error;
          });
        }
      },
    );
  }

  void _finishCollection() {
    // Clear callback to avoid listening in other screens
    ChestStrapService().onDataReceived = null;
    
    setState(() => _phase = _Phase.calculating);
    Future.delayed(const Duration(milliseconds: 300), _computeAndUpload);
  }

  // ═══════════════════════════════════════════════════════════════
  // Statistics & Upload
  // ═══════════════════════════════════════════════════════════════

  Future<void> _computeAndUpload() async {
    if (_collectedReadings.isEmpty) {
      setState(() {
        _errorMessage = 'No baseline data was collected from the chest strap.';
        _phase = _Phase.error;
      });
      return;
    }

    // Convert readings into 10-feature windows
    final List<List<double>> featuresPerWindow = _collectedReadings.map((r) => [
      r.meanHR,
      r.meanRR,
      r.sdnn,
      r.rmssd,
      r.meanBR,
      r.stdBR,
      r.meanTemp,
      r.stdTemp,
      r.meanAccMag,
      r.stdAccMag,
    ]).toList();

    // Compute mean and standard deviation across the windows for each of the 10 features
    final List<double> finalMeans = List.filled(10, 0.0);
    final List<double> finalStds = List.filled(10, 0.0);

    for (int f = 0; f < 10; f++) {
      final List<double> vals = featuresPerWindow.map((win) => win[f]).toList();
      final double meanVal = vals.reduce((a, b) => a + b) / vals.length;
      finalMeans[f] = meanVal;

      if (vals.length < 2) {
        finalStds[f] = 1e-6; // standard fallback
      } else {
        final double varSum = vals.map((x) => (x - meanVal) * (x - meanVal)).reduce((a, b) => a + b);
        double stdVal = sqrt(varSum / vals.length);
        if (stdVal < 1e-6) stdVal = 1e-6;
        finalStds[f] = stdVal;
      }
    }

    setState(() {
      _uploading = true;
      _restingHR = finalMeans[0];
      _restingBR = finalMeans[4];
      _restingTemp = finalMeans[6];
    });

    // Upload to server normalization endpoint
    bool ok = false;
    try {
      ok = await ApiService.setNormalizationParams(
        userId: widget.userId,
        bMean: finalMeans,
        bStd: finalStds,
      );
    } catch (e) {
      ok = false;
      debugPrint('Calibration upload error: $e');
    }

    // Persist the calibration complete flag locally
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('calibration_complete', true);
    }

    if (!mounted) return;
    setState(() {
      _uploading = false;
      _phase = ok ? _Phase.done : _Phase.error;
      if (!ok) {
        _errorMessage = 'Could not reach the server. Please check your internet connection and try again.';
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Navigation
  // ═══════════════════════════════════════════════════════════════

  void _proceed() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MainNavigationPage(userId: widget.userId),
        transitionsBuilder: (context, anim, secondaryAnimation, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 700),
      ),
    );
  }

  void _skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('calibration_complete', true);
    if (mounted) _proceed();
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.instructions:
        return _buildInstructionsView();
      case _Phase.collecting:
        return _buildCollectingView();
      case _Phase.calculating:
        return _buildCalculatingView();
      case _Phase.done:
        return _buildDoneView();
      case _Phase.error:
        return _buildErrorView();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Phase 1 — Instructions
  // ─────────────────────────────────────────────────────────────

  Widget _buildInstructionsView() {
    final bool isStrapConnected = ChestStrapService().isConnected;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),

          // Pulsing heart icon
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.monitor_heart_outlined,
                  color: Colors.white,
                  size: 52,
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          Text(
            'Baseline Calibration',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'Before Aura can accurately analyze anxiety patterns, '
            'it needs to learn your resting baseline from the chest strap.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.6,
            ),
          ),

          const SizedBox(height: 36),

          // Step cards
          _StepCard(
            number: '1',
            icon: Icons.self_improvement_rounded,
            title: 'Find a comfortable position',
            description:
                'Sit or lie down in a relaxed state. Try not to move around.',
          ),
          const SizedBox(height: 14),
          _StepCard(
            number: '2',
            icon: Icons.timer_outlined,
            title: 'Record 3 windows',
            description:
                'The chest strap will record 3 consecutive sixty-second resting windows.',
          ),
          const SizedBox(height: 14),
          _StepCard(
            number: '3',
            icon: Icons.cloud_upload_outlined,
            title: 'Data is uploaded securely',
            description:
                'Your resting baseline parameter stats are stored on the server — never raw readings.',
          ),

          const SizedBox(height: 28),

          // Calm state warning card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'IMPORTANT: Only calibrate when you are feeling calm and relaxed. '
                    'If you are currently stressed or active, please skip and calibrate later, '
                    'as calibrating now will cause inaccurate stress calculations.',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.9),
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Connection Warning banner if strap disconnected
          if (!isStrapConnected) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFF8A80), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_disabled_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Strap is disconnected. Please go back to the Vitals tab and connect your ChestStrap_V3 before attempting calibration.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Start button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isStrapConnected ? _startCalibration : null,
              icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
              label: Text(
                'Start Calibration',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF667eea),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.3),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Skip link
          TextButton(
            onPressed: _skip,
            child: Text(
              'Skip for now (use global defaults)',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.65),
                decoration: TextDecoration.underline,
                decorationColor: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Phase 2 — Collecting
  // ─────────────────────────────────────────────────────────────

  Widget _buildCollectingView() {
    final double elapsedPercent = _elapsedSeconds / _calibrationDurationSeconds;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Recording Baseline',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Stay still and breathe normally.',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),

          const SizedBox(height: 48),

          // Animated visualizer
          _WaveformVisualizer(animation: _waveAnimation),

          const SizedBox(height: 48),

          // Circular progress window counter
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(
                          alpha: 0.06 * _pulseAnimation.value),
                    ),
                  ),
                  // Progress ring
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                      value: elapsedPercent.clamp(0.01, 1.0),
                      strokeWidth: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  // Counter display
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_elapsedSeconds/$_calibrationDurationSeconds',
                        style: GoogleFonts.poppins(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -1,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'seconds',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 48),

          Text(
            'Recording baseline data for 3 minutes. Packets received: ${_collectedReadings.length}.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white24),
          const SizedBox(height: 16),

          Text(
            'Elapsed Time: $_elapsedSeconds seconds',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Phase 3 — Calculating
  // ─────────────────────────────────────────────────────────────

  Widget _buildCalculatingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
            const SizedBox(height: 32),
            Text(
              _uploading ? 'Uploading Baseline Parameters' : 'Processing Baseline',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _uploading
                  ? 'Saving your personalised baseline parameters securely to server.'
                  : 'Calculating statistical bounds for each sensor parameter.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.75),
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Phase 4 — Done (success)
  // ─────────────────────────────────────────────────────────────

  Widget _buildDoneView() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        children: [
          // Success icon
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.white,
                  size: 60,
                ),
              ),
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Calibration Complete!',
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'Your resting baseline parameters have been securely uploaded. '
            'The prediction model is now personalised to your physiology.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.6,
            ),
          ),

          const SizedBox(height: 32),

          // Summary stats card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Calibration Summary',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                _summaryRow('Duration', '3 minutes'),
                _summaryRow('Data windows', '${_collectedReadings.length}'),
                _summaryRow('Features extracted', '10'),
                _summaryRow(
                    'Resting HR', '${_restingHR.toStringAsFixed(1)} BPM'),
                _summaryRow(
                    'Resting BR', '${_restingBR.toStringAsFixed(1)} breaths/min'),
                _summaryRow(
                    'Resting Temp', '${_restingTemp.toStringAsFixed(2)} °C'),
                _summaryRow('Upload status', 'Success ✓'),
              ],
            ),
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _proceed,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(
                'Go to Dashboard',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF667eea),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Phase 5 — Error
  // ─────────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              color: Colors.white,
              size: 50,
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Upload Failed',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            _errorMessage ?? 'An unexpected error occurred.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.6,
            ),
          ),

          const SizedBox(height: 36),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _computeAndUpload,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                'Retry Upload',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF667eea),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
            ),
          ),

          const SizedBox(height: 14),

          TextButton(
            onPressed: _skip,
            child: Text(
              'Skip and continue without calibration',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.65),
                decoration: TextDecoration.underline,
                decorationColor: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase Enum
// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { instructions, collecting, calculating, done, error }

// ─────────────────────────────────────────────────────────────────────────────
// Step Card widget
// ─────────────────────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String description;

  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number bubble
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon,
                        color: Colors.white.withValues(alpha: 0.8), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.75),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated ECG-style waveform visualizer
// ─────────────────────────────────────────────────────────────────────────────

class _WaveformVisualizer extends StatelessWidget {
  final Animation<double> animation;
  const _WaveformVisualizer({required this.animation});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) => CustomPaint(
          painter: _WaveformPainter(phase: animation.value),
          size: const Size(double.infinity, 80),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double phase;
  _WaveformPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final double w = size.width;
    final double h = size.height;
    final double cx = h / 2;

    const int segments = 200;
    for (int i = 0; i <= segments; i++) {
      final double x = (i / segments) * w;
      final double t = (i / segments + phase) * 2 * pi;
      final double ecgPhase = (i / segments + phase) % 1.0;

      double y;
      final double beatPhase = (ecgPhase * 8) % 1.0;
      if (beatPhase < 0.05) {
        y = cx - 8 * sin(beatPhase / 0.05 * pi);
      } else if (beatPhase < 0.1) {
        y = cx;
      } else if (beatPhase < 0.12) {
        y = cx + 6 * sin((beatPhase - 0.1) / 0.02 * pi);
      } else if (beatPhase < 0.15) {
        y = cx - 28 * sin((beatPhase - 0.12) / 0.03 * pi);
      } else if (beatPhase < 0.18) {
        y = cx + 10 * sin((beatPhase - 0.15) / 0.03 * pi);
      } else if (beatPhase < 0.35) {
        y = cx - 6 * sin((beatPhase - 0.18) / 0.17 * pi);
      } else {
        y = cx + 0.5 * sin(t * 2);
      }

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.phase != phase;
}
