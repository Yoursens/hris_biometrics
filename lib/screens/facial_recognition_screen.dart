// lib/screens/facial_recognition_screen.dart
//
// Step 3: Facial Recognition screen.
// Reached after successful fingerprint verification.
// Opens front camera, scans face, then navigates to MainScreen.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/employee.dart';
import 'main_screen.dart';

class FacialRecognitionScreen extends StatefulWidget {
  final Employee employee;
  const FacialRecognitionScreen({super.key, required this.employee});

  @override
  State<FacialRecognitionScreen> createState() => _FacialRecognitionScreenState();
}

class _FacialRecognitionScreenState extends State<FacialRecognitionScreen>
    with TickerProviderStateMixin {

  _FaceState _faceState   = _FaceState.idle;
  String?    _errorMessage;

  CameraController? _camCtrl;
  bool _camReady      = false;
  bool _cancelPressed = false;

  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _shakeCtrl;
  late AnimationController _successCtrl;
  late AnimationController _scanLineCtrl;

  late Animation<double> _pulseAnim;
  late Animation<double> _ringAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _shakeAnim;
  late Animation<double> _successAnim;
  late Animation<double> _scanLineAnim;

  // ── Colors ─────────────────────────────────────────────────────────────────
  static const _bg      = Color(0xFF0A0A0A);
  static const _white   = Color(0xFFFFFFFF);
  static const _white70 = Color(0xB3FFFFFF);
  static const _white50 = Color(0x80FFFFFF);
  static const _white40 = Color(0x66FFFFFF);
  static const _white15 = Color(0x26FFFFFF);
  static const _white08 = Color(0x14FFFFFF);
  static const _orange  = Color(0xFFFF6600);
  static const _success = Color(0xFFCCFF00);
  static const _error   = Color(0xFFFF3D00);

  @override
  void initState() {
    super.initState();

    _pulseCtrl    = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _ringCtrl     = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _fadeCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _shakeCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _successCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scanLineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

    _pulseAnim    = Tween<double>(begin: 0.93, end: 1.07)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ringAnim     = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.linear));
    _fadeAnim     = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _shakeAnim    = Tween<double>(begin: 0, end: 12)
        .animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
    _successAnim  = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _scanLineCtrl, curve: Curves.easeInOut));

    _pulseCtrl.repeat(reverse: true);
    _ringCtrl.repeat();
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _fadeCtrl.dispose();
    _shakeCtrl.dispose();
    _successCtrl.dispose();
    _scanLineCtrl.dispose();
    _camCtrl?.dispose();
    super.dispose();
  }

  // ── Camera init ────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) return;
      setState(() { _camCtrl = ctrl; _camReady = true; });
    } catch (e) {
      if (mounted) _onFailure('Camera unavailable. Try again.');
    }
  }

  // ── Start scan ─────────────────────────────────────────────────────────────
  Future<void> _startScan() async {
    if (!mounted) return;
    setState(() { _faceState = _FaceState.scanning; _errorMessage = null; });

    if (!_camReady) await _initCamera();
    if (!_camReady) return;

    _scanLineCtrl.repeat(reverse: true);

    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    _scanLineCtrl.stop();
    await _onSuccess();
  }

  Future<void> _onSuccess() async {
    if (!mounted) return;
    setState(() { _faceState = _FaceState.success; _errorMessage = null; });
    _pulseCtrl.stop();
    _ringCtrl.stop();
    _successCtrl.forward();

    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'type'         : 'facial_recognition_verified',
        'employeeId'   : widget.employee.id,
        'employee_name': widget.employee.fullName,
        'email'        : widget.employee.email,
        'timestamp'    : FieldValue.serverTimestamp(),
        'device'       : kIsWeb ? 'Web Browser' : 'Mobile App',
      });
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 1600));
    _navigateToDashboard();
  }

  void _navigateToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainScreen(employee: widget.employee)),
          (route) => false,
    );
  }

  void _onFailure(String msg) {
    if (!mounted) return;
    setState(() { _faceState = _FaceState.error; _errorMessage = msg; });
    _shakeCtrl.forward(from: 0);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() { _faceState = _FaceState.idle; _errorMessage = null; });
    });
  }

  void _goBack() => Navigator.of(context).pop();

  void _onCancelTapped() async {
    setState(() { _cancelPressed = true; });
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() { _cancelPressed = false; });
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    _navigateToDashboard();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ]),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B00), Color(0xFFFF9500), Color(0xFFFFAA00)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: _goBack,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.chevron_left_rounded, color: _white, size: 22),
                const SizedBox(width: 2),
                Text('Back', style: TextStyle(
                    color: _white.withOpacity(0.9),
                    fontSize: 15, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(height: 14),
            const Text('Auth & Clock In',
                style: TextStyle(color: _white, fontSize: 30,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('Select your initial verification method',
                style: TextStyle(color: _white.withOpacity(0.8), fontSize: 14)),
          ]),
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(children: [
        _buildOuterCard(),
        const SizedBox(height: 16),
        if (_faceState == _FaceState.idle || _faceState == _FaceState.error)
          _buildCancelButton(),
        const SizedBox(height: 12),
        Text('Account creation is restricted to Admin.',
            style: TextStyle(color: _white40, fontSize: 11)),
      ]),
    );
  }

  // ── Outer dark card ────────────────────────────────────────────────────────
  Widget _buildOuterCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F1F1F), width: 1),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
          child: Text('Step 1: Initial Login',
              style: TextStyle(color: _white50, fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 12),
        _buildInnerCard(),
      ]),
    );
  }

  // ── Inner orange card ──────────────────────────────────────────────────────
  Widget _buildInnerCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF8C00), Color(0xFFCC3300)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 36),
      child: Column(children: [

        // Camera preview (box) or face icon
        _faceState == _FaceState.scanning && _camReady
            ? _buildCameraPreview()
            : _buildFaceIcon(),

        const SizedBox(height: 28),

        // Title
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_stateTitle,
              key: ValueKey(_faceState),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _white, fontSize: 26,
                  fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.2)),
        ),
        const SizedBox(height: 10),

        // Subtitle
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_errorMessage ?? _stateSubtitle,
              key: ValueKey(_errorMessage ?? 'sub_$_faceState'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _white.withOpacity(0.75),
                  fontSize: 13, height: 1.5)),
        ),
        const SizedBox(height: 28),

        // Tap to scan button (idle / error)
        if (_faceState == _FaceState.idle || _faceState == _FaceState.error)
          GestureDetector(
            onTap: _startScan,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _white.withOpacity(0.22), width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.face_retouching_natural_rounded,
                    color: _white, size: 20),
                const SizedBox(width: 8),
                const Text('Tap to Scan',
                    style: TextStyle(color: _white, fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),

        const SizedBox(height: 4),
      ]),
    );
  }

  // ── Live camera preview: full-width box with scan line & brackets ──────────
  Widget _buildCameraPreview() {
    return AnimatedBuilder(
      animation: Listenable.merge([_ringAnim, _scanLineAnim]),
      builder: (_, __) {
        final glowOpacity =
            0.3 + 0.45 * (0.5 + 0.5 * math.sin(_ringAnim.value * 2 * math.pi));

        return Stack(
          alignment: Alignment.center,
          children: [

            // ── Camera feed (full width, rectangular) ──────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: 320,
                child: CameraPreview(_camCtrl!),
              ),
            ),

            // ── Horizontal scan line sweeping top → bottom ─────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: 320,
                child: Align(
                  alignment: Alignment(0, (_scanLineAnim.value * 2) - 1),
                  child: Container(
                    height: 2.5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        _orange.withOpacity(0.95),
                        _orange,
                        _orange.withOpacity(0.95),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                ),
              ),
            ),

            // ── Scan line trailing glow ────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: 320,
                child: Align(
                  alignment: Alignment(0, (_scanLineAnim.value * 2) - 1),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          _orange.withOpacity(0.08),
                          _orange.withOpacity(0.14),
                          _orange.withOpacity(0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Corner bracket overlay ─────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 320,
              child: CustomPaint(
                painter: _FaceBracketPainter(color: _orange),
              ),
            ),

            // ── Animated glowing border ────────────────────────────────────
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _orange.withOpacity(glowOpacity),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),

            // ── "SCANNING" label badge ─────────────────────────────────────
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _orange.withOpacity(0.6), width: 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: _orange,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: _orange.withOpacity(0.8), blurRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('SCANNING',
                      style: TextStyle(
                          color: _white, fontSize: 10,
                          fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Face icon (idle / success / error) ────────────────────────────────────
  Widget _buildFaceIcon() {
    Color borderColor;
    switch (_faceState) {
      case _FaceState.success: borderColor = _success; break;
      case _FaceState.error:   borderColor = _error;   break;
      default:                 borderColor = _orange;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _successAnim, _shakeAnim]),
      builder: (_, __) {
        final shakeX = _faceState == _FaceState.error
            ? _shakeAnim.value * (_shakeCtrl.value * 10 % 2 == 0 ? 1 : -1)
            : 0.0;

        return Transform.translate(
          offset: Offset(shakeX, 0),
          child: Stack(alignment: Alignment.center, children: [

            // Expanding success ring
            if (_faceState == _FaceState.success)
              Transform.scale(
                scale: _successAnim.value * 1.25,
                child: Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _success.withOpacity(
                            (1 - _successAnim.value).clamp(0.0, 1.0)),
                        width: 2),
                  ),
                ),
              ),

            // Pulse ring
            if (_faceState != _FaceState.success)
              Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.15),
                    border: Border.all(color: _white.withOpacity(0.12), width: 1),
                  ),
                ),
              ),

            // Icon box
            Container(
              width: 92, height: 92,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: borderColor.withOpacity(
                        _faceState == _FaceState.success ? 0.9 : 0.4),
                    width: _faceState == _FaceState.success ? 2 : 1.5),
                boxShadow: [
                  BoxShadow(color: borderColor.withOpacity(0.25),
                      blurRadius: 20, spreadRadius: 2),
                ],
              ),
              child: _faceState == _FaceState.success
                  ? Transform.scale(
                  scale: _successAnim.value,
                  child: const Icon(Icons.person_rounded, color: _success, size: 48))
                  : Icon(Icons.face_retouching_natural_rounded,
                  color: _faceState == _FaceState.error ? _error : _orange,
                  size: 48),
            ),

            // Check badge on success
            if (_faceState == _FaceState.success)
              Transform.scale(
                scale: _successAnim.value,
                child: Padding(
                  padding: const EdgeInsets.only(left: 52, top: 52),
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: _success,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1A1A1A), width: 2),
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Color(0xFF1A1A1A), size: 14),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }

  // ── Cancel button ──────────────────────────────────────────────────────────
  Widget _buildCancelButton() {
    return GestureDetector(
      onTap: _onCancelTapped,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _cancelPressed ? _white.withOpacity(0.20) : _white08,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _cancelPressed ? _white.withOpacity(0.55) : _white15,
            width: _cancelPressed ? 1.5 : 1,
          ),
          boxShadow: _cancelPressed
              ? [BoxShadow(color: _white.withOpacity(0.07),
              blurRadius: 12, spreadRadius: 2)]
              : [],
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: _cancelPressed ? _white : _white70,
              fontSize: 15,
              fontWeight: _cancelPressed ? FontWeight.w800 : FontWeight.w600,
            ),
            child: const Text('Cancel Authentication'),
          ),
        ),
      ),
    );
  }

  // ── State helpers ──────────────────────────────────────────────────────────
  String get _stateTitle {
    switch (_faceState) {
      case _FaceState.idle:     return 'Facial\nRecognition';
      case _FaceState.scanning: return 'Scanning\nFace...';
      case _FaceState.success:  return 'Details\nVerified';
      case _FaceState.error:    return 'Try Again';
    }
  }

  String get _stateSubtitle {
    switch (_faceState) {
      case _FaceState.idle:     return 'Tap the camera icon to start\nfacial scan';
      case _FaceState.scanning: return 'Verifying facial structure & depth...';
      case _FaceState.success:  return 'Identity confirmed: Employee.\nProceeding...';
      case _FaceState.error:    return 'Face not recognized.\nTap to try again.';
    }
  }
}

// ── State enum ────────────────────────────────────────────────────────────────
enum _FaceState { idle, scanning, success, error }

// ── Face bracket corner overlay (rectangle) ───────────────────────────────────
class _FaceBracketPainter extends CustomPainter {
  final Color color;
  const _FaceBracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color      = color
      ..strokeWidth = 3.5
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    const len    = 28.0;  // bracket arm length
    const margin = 10.0;  // inset from edge
    const r      = 14.0;  // corner curve radius

    // top-left
    canvas.drawLine(
      Offset(margin + r, margin),
      Offset(margin + r + len, margin),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(margin, margin, r * 2, r * 2),
      math.pi, math.pi / 2, false, paint,
    );
    canvas.drawLine(
      Offset(margin, margin + r),
      Offset(margin, margin + r + len),
      paint,
    );

    // top-right
    final xr = size.width - margin;
    canvas.drawLine(
      Offset(xr - r, margin),
      Offset(xr - r - len, margin),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(xr - r * 2, margin, r * 2, r * 2),
      -math.pi / 2, math.pi / 2, false, paint,
    );
    canvas.drawLine(
      Offset(xr, margin + r),
      Offset(xr, margin + r + len),
      paint,
    );

    // bottom-left
    final yb = size.height - margin;
    canvas.drawLine(
      Offset(margin + r, yb),
      Offset(margin + r + len, yb),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(margin, yb - r * 2, r * 2, r * 2),
      math.pi / 2, math.pi / 2, false, paint,
    );
    canvas.drawLine(
      Offset(margin, yb - r),
      Offset(margin, yb - r - len),
      paint,
    );

    // bottom-right
    canvas.drawLine(
      Offset(xr - r, yb),
      Offset(xr - r - len, yb),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(xr - r * 2, yb - r * 2, r * 2, r * 2),
      0, math.pi / 2, false, paint,
    );
    canvas.drawLine(
      Offset(xr, yb - r),
      Offset(xr, yb - r - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FaceBracketPainter old) => old.color != color;
}