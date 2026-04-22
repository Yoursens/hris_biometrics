// lib/screens/login_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/security_service.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/location_tracking_service.dart';
import '../models/employee.dart';
import 'main_screen.dart';
import 'landing_screen.dart';
import 'package:firebase_core/firebase_core.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  String _pinInput = '';
  bool _isLoading = false;
  bool _nfcAvailable = false;
  String? _errorMessage;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  late AnimationController _rotateController;
  late Animation<double> _rotateAnim;

  String _statusAction = '';
  String _currentTime = '';

  // ── Design tokens (matching landing screen) ──
  static const Color _navy     = Color(0xFF0A0F2E);
  static const Color _navyLight = Color(0xFF131A45);
  static const Color _accent   = Color(0xFF00D4FF);
  static const Color _white    = Color(0xFFFFFFFF);
  static const Color _white70  = Color(0xB3FFFFFF);
  static const Color _white40  = Color(0x66FFFFFF);
  static const Color _white15  = Color(0x26FFFFFF);
  static const Color _white08  = Color(0x14FFFFFF);
  static const Color _success  = Color(0xFF00E5A0);
  static const Color _error    = Color(0xFFFF4D6D);

  @override
  void initState() {
    super.initState();

    // 1. Setup Controllers
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _rotateController = AnimationController(vsync: this, duration: const Duration(seconds: 12));

    // 2. Setup Animations IMMEDIATELY
    _shakeAnim = Tween<double>(begin: 0, end: 10).animate(
        CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));
    
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    
    _rotateAnim = Tween<double>(begin: 0, end: 2 * math.pi).animate(
        CurvedAnimation(parent: _rotateController, curve: Curves.linear));

    // 3. Start Animations
    _pulseController.repeat(reverse: true);
    _rotateController.repeat();
    _fadeController.forward();

    _checkCapabilities();
  }

  Future<void> _checkCapabilities() async {
    if (kIsWeb) return;
    try {
      final nfcAvailable = await NfcManager.instance.isAvailable();
      if (mounted) setState(() => _nfcAvailable = nfcAvailable);
      if (nfcAvailable) _startNfcSession();
    } catch (e) {
      debugPrint('NFC Capability Check Error: $e');
    }
  }

  Future<void> _startNfcSession() async {
    if (kIsWeb) return;
    try {
      await NfcManager.instance.stopSession();
      NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        onDiscovered: (NfcTag tag) async {
          if (_isLoading) return;
          final tagId = _extractTagId(tag);
          if (tagId == null) { _setError('Could not read tag ID.'); return; }
          final now = DateTime.now();
          final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
          if (mounted) setState(() => _currentTime = timeStr);
          try {
            setState(() { _isLoading = true; _errorMessage = null; });
            final employee = await DatabaseService.instance.getEmployeeByNfcTag(tagId);
            if (employee != null) {
              if (mounted) {
                setState(() => _statusAction = 'LOGIN SUCCESS');
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Welcome, ${employee.fullName}!'),
                  backgroundColor: _success,
                  duration: const Duration(seconds: 1),
                ));
              }
              await NfcManager.instance.stopSession();
              await _openSession(employee);
            } else {
              await NfcManager.instance.stopSession();
              if (mounted) {
                setState(() { _statusAction = 'UNREGISTERED TAG'; _isLoading = false; });
                _setError('Keyfob not registered. Please contact Admin.');
              }
            }
          } catch (e) { _setError('NFC login error: $e'); }
        },
      );
    } catch (e) { debugPrint('NFC session error: $e'); }
  }

  String? _extractTagId(NfcTag tag) {
    try {
      final tagMap = tag.data as Map<String, dynamic>;
      List<int>? tryKey(String key) {
        final tech = tagMap[key] as Map<dynamic, dynamic>?;
        if (tech == null) return null;
        final raw = tech['identifier'];
        if (raw is List) return raw.cast<int>();
        return null;
      }
      final id = tryKey('nfca') ?? tryKey('nfcb') ?? tryKey('nfcf') ??
          tryKey('nfcv') ?? tryKey('isodep') ?? tryKey('mifare-classic') ??
          tryKey('mifare-ultralight');
      if (id == null || id.isEmpty) return null;
      return id.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
    } catch (_) { return null; }
  }

  Future<void> _loginWithPin() async {
    if (_pinInput.length < 4) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      Employee? matchedEmployee;
      try {
        final query = await FirebaseFirestore.instance
            .collection('employees')
            .where('status', isEqualTo: 'active')
            .get()
            .catchError((e) {
          debugPrint('Firestore query error: $e');
          return null;
        });
        if (query == null) throw 'Could not reach server.';
        for (var doc in query.docs) {
          final data = doc.data();
          final tempPin = data['tempPin'] as String?;
          if (tempPin != null && tempPin == _pinInput) {
            final normalizedData = {
              'id': doc.id,
              'employee_id': data['employeeId'] ?? '',
              'first_name': data['firstName'] ?? '',
              'last_name': data['lastName'] ?? '',
              'email': data['email'] ?? '',
              'department': data['department'] ?? '',
              'position': data['position'] ?? '',
              'phone': data['phone'],
              'photo_path': data['photoPath'],
              'face_embedding': data['faceEmbedding'],
              'fingerprint_hash': data['fingerprintHash'],
              'pin_hash': null,
              'pin_salt': null,
              'nfc_tag_id': data['nfcTagId'],
              'is_active': data['status'] == 'active' ? 1 : 0,
              'created_at': data['createdAt']?.toDate().toIso8601String() ?? DateTime.now().toIso8601String(),
              'updated_at': data['updatedAt']?.toDate().toIso8601String() ?? DateTime.now().toIso8601String(),
            };
            matchedEmployee = Employee.fromMap(normalizedData);
            if (!kIsWeb) await DatabaseService.instance.insertEmployee(matchedEmployee);
            break;
          }
        }
      } catch (firestoreError) { debugPrint('Firestore error: $firestoreError'); }

      if (matchedEmployee == null && !kIsWeb) {
        final localEmployees = await DatabaseService.instance.getAllEmployees();
        for (var emp in localEmployees) {
          final isValid = await SecurityService.instance.verifyPin(emp.id, _pinInput);
          if (isValid) { matchedEmployee = emp; break; }
        }
      }
      if (matchedEmployee == null) throw 'Invalid PIN. Please try again.';
      await _openSession(matchedEmployee);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().contains('Invalid')
              ? 'Invalid PIN. Please try again.'
              : 'Session error: ${e.toString()}';
          _isLoading = false;
          _pinInput = '';
        });
        _shakeController.forward(from: 0);
      }
    }
  }

  Future<void> _openSession(Employee employee) async {
    try {
      await SecurityService.instance.createSession(employee.id);
      if (!kIsWeb) LocationTrackingService.instance.startTracking(employee.id);
      try {
        await FirebaseFirestore.instance.collection('activity_logs').add({
          'type': 'login',
          'employee_id': employee.employeeId,
          'employee_name': employee.fullName,
          'timestamp': FieldValue.serverTimestamp(),
          'device': kIsWeb ? 'Web Browser' : 'Mobile App',
        });
      } on FirebaseException catch (e) {
        debugPrint('Firebase log error: ${e.message}');
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainScreen(employee: employee)),
            (route) => false,
      );
    } catch (e) {
      if (mounted) setState(() { _errorMessage = 'Session error: $e'; _isLoading = false; });
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() { _errorMessage = msg; _isLoading = false; _pinInput = ''; });
      _shakeController.forward(from: 0);
    }
  }

  void _onPinKey(String key) {
    if (_isLoading) return;
    setState(() => _errorMessage = null);
    if (key == 'del') {
      if (_pinInput.isNotEmpty) {
        setState(() => _pinInput = _pinInput.substring(0, _pinInput.length - 1));
      }
    } else if (_pinInput.length < 4) {
      setState(() => _pinInput += key);
      if (_pinInput.length == 4) {
        Future.delayed(const Duration(milliseconds: 250), _loginWithPin);
      }
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _rotateController.dispose();
    if (!kIsWeb) {
      try { NfcManager.instance.stopSession(); } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const LandingScreen()));
      },
      child: Scaffold(
        backgroundColor: _navy,
        body: FadeTransition(
          opacity: _fadeAnim,
          child: Stack(
            children: [
              // Ambient background glow
              Positioned(
                top: -100,
                right: -100,
                child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      _accent.withOpacity(0.07),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
              Positioned(
                bottom: -150,
                left: -100,
                child: Container(
                  width: 350,
                  height: 350,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFFFFBB00).withOpacity(0.05),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),

              // Main content
              SafeArea(
                child: isWide
                    ? _buildWideLayout()
                    : _buildNarrowLayout(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── WIDE (tablet/web) layout ─────────────────────────────────────────────
  Widget _buildWideLayout() {
    return Row(
      children: [
        // Left panel
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              color: _white08,
              border: Border(right: BorderSide(color: _white15, width: 0.5)),
            ),
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogoMark(size: 72),
                const SizedBox(height: 24),
                const Text('HRIS', style: TextStyle(
                    color: _white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 3)),
                Text('BIOMETRICS', style: TextStyle(
                    color: _accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 4)),
                const SizedBox(height: 48),
                _buildOrbAnimation(),
                const SizedBox(height: 40),
                if (!kIsWeb && _nfcAvailable) _buildNfcSection(),
                const SizedBox(height: 24),
                Text(
                  'Tap your keyfob or enter\nyour PIN to sign in',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white40, fontSize: 13, height: 1.6),
                ),
              ],
            ),
          ),
        ),
        // Right panel
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeader(),
                const SizedBox(height: 48),
                if (_statusAction.isNotEmpty) ...[
                  _buildStatusBanner(),
                  const SizedBox(height: 32),
                ],
                _buildPinSection(),
                const SizedBox(height: 32),
                _buildPinPad(isWide: true),
                const SizedBox(height: 24),
                _buildFeedback(),
                const SizedBox(height: 32),
                _buildFooterNote(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── NARROW (phone) layout ────────────────────────────────────────────────
  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 40),
          _buildLogoRow(),
          const SizedBox(height: 40),
          _buildOrbAnimation(size: 160),
          if (!kIsWeb && _nfcAvailable) ...[
            const SizedBox(height: 28),
            _buildNfcSection(),
          ],
          if (_statusAction.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildStatusBanner(),
          ],
          const SizedBox(height: 36),
          _buildPinSection(),
          const SizedBox(height: 28),
          _buildPinPad(isWide: false),
          const SizedBox(height: 20),
          _buildFeedback(),
          const SizedBox(height: 24),
          _buildFooterNote(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── WIDGETS ──────────────────────────────────────────────────────────────

  Widget _buildLogoMark({double size = 56}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00D4FF), Color(0xFF0055BB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(Icons.fingerprint_rounded, color: Colors.white, size: size * 0.52),
    );
  }

  Widget _buildLogoRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLogoMark(size: 44),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('HRIS', style: TextStyle(
                color: _white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2.5)),
            Text('BIOMETRICS', style: TextStyle(
                color: _accent, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 3.5)),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _accent.withOpacity(0.35), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 6,
                  decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('Secure Login', style: TextStyle(
                  color: _accent, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Welcome\nBack', style: TextStyle(
            fontSize: 44, fontWeight: FontWeight.w900, color: _white,
            height: 1.1, letterSpacing: -1.5)),
        const SizedBox(height: 12),
        Text('Enter your 4-digit PIN to access\nthe attendance system.',
            style: TextStyle(fontSize: 14, color: _white70, height: 1.6)),
      ],
    );
  }

  Widget _buildOrbAnimation({double size = 200}) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _rotateAnim]),
      builder: (_, __) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: _rotateAnim.value,
              child: CustomPaint(
                size: Size(size, size),
                painter: _DashRingPainter(color: _accent, opacity: 0.3),
              ),
            ),
            Transform.rotate(
              angle: -_rotateAnim.value * 0.6,
              child: CustomPaint(
                size: Size(size * 0.78, size * 0.78),
                painter: _DashRingPainter(
                    color: const Color(0xFFFFBB00), opacity: 0.2, dashCount: 10),
              ),
            ),
            Transform.scale(
              scale: _pulseAnim.value,
              child: Container(
                width: size * 0.6,
                height: size * 0.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    _accent.withOpacity(0.18),
                    _navy.withOpacity(0.95),
                  ]),
                  border: Border.all(color: _accent.withOpacity(0.55), width: 1.5),
                ),
                child: Icon(Icons.shield_rounded,
                    color: _accent.withOpacity(0.9), size: size * 0.28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNfcSection() {
    return GestureDetector(
      onTap: _isLoading ? null : _startNfcSession,
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Transform.scale(
              scale: _isLoading ? 1.0 : _pulseAnim.value * 0.97,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withOpacity(0.1),
                  border: Border.all(color: _accent.withOpacity(0.5), width: 1.5),
                ),
                child: _isLoading
                    ? const Center(child: SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                        color: _accent, strokeWidth: 2)))
                    : const Icon(Icons.contactless_rounded, color: _accent, size: 34),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(_isLoading ? 'Reading...' : 'TAP KEYFOB',
              style: TextStyle(
                  color: _isLoading ? _white40 : _accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final isSuccess = _statusAction == 'LOGIN SUCCESS';
    final color = isSuccess ? _success : _error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withOpacity(0.15)),
            child: Icon(
                isSuccess ? Icons.check_circle_rounded : Icons.contactless_rounded,
                color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_statusAction, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color)),
              if (_currentTime.isNotEmpty)
                Text('Time: $_currentTime',
                    style: TextStyle(color: color.withOpacity(0.7), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPinSection() {
    return Column(
      children: [
        Row(
          children: [
            Text('Access PIN', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: _white70, letterSpacing: 0.5)),
            const Spacer(),
            Text('4 digits', style: TextStyle(fontSize: 12, color: _white40)),
          ],
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: _shakeAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(
                _shakeAnim.value *
                    ((_shakeController.value * 10).round().isEven ? 1 : -1),
                0),
            child: child,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < _pinInput.length;
              final hasError = _errorMessage != null;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 10),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasError
                      ? _error.withOpacity(filled ? 1 : 0)
                      : filled ? _accent : Colors.transparent,
                  border: Border.all(
                    color: hasError
                        ? _error.withOpacity(0.7)
                        : filled ? _accent : _white40,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildPinPad({required bool isWide}) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 360 : double.infinity),
        child: Column(
          children: List.generate(4, (rowIdx) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: List.generate(3, (colIdx) {
                  final key = rows[rowIdx][colIdx];
                  if (key.isEmpty) return const Expanded(child: SizedBox());
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          left: colIdx > 0 ? 10 : 0,
                          right: colIdx < 2 ? 10 : 0),
                      child: _PinKey(
                        label: key,
                        onTap: () => _onPinKey(key),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildFeedback() {
    if (_isLoading) {
      return const SizedBox(
        height: 36,
        child: Center(
          child: SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(color: _accent, strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _error.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: _error, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(_errorMessage!,
                  style: TextStyle(color: _error, fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: 36);
  }

  Widget _buildFooterNote() {
    return Text(
      'Account creation is restricted to Admin.',
      style: TextStyle(color: _white40, fontSize: 11),
    );
  }
}

// ── PIN KEY BUTTON ─────────────────────────────────────────────────────────
class _PinKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _PinKey({required this.label, required this.onTap});

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scaleAnim;

  static const Color _navy    = Color(0xFF0A0F2E);
  static const Color _accent  = Color(0xFF00D4FF);
  static const Color _white   = Color(0xFFFFFFFF);
  static const Color _white15 = Color(0x26FFFFFF);
  static const Color _white08 = Color(0x14FFFFFF);

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.93).animate(
        CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDel = widget.label == 'del';
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) { _pressCtrl.reverse(); widget.onTap(); },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: isDel ? _white08 : _white15,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDel
                  ? const Color(0x26FFFFFF)
                  : _accent.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Center(
            child: isDel
                ? const Icon(Icons.backspace_outlined,
                color: Color(0xB3FFFFFF), size: 22)
                : Text(widget.label,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: _white)),
          ),
        ),
      ),
    );
  }
}

// ── DASH RING PAINTER ──────────────────────────────────────────────────────
class _DashRingPainter extends CustomPainter {
  final Color color;
  final double opacity;
  final int dashCount;

  _DashRingPainter({required this.color, required this.opacity, this.dashCount = 16});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 2;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dashAngle = (2 * math.pi) / dashCount;
    final gapFraction = 0.4;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      final sweepAngle = dashAngle * (1 - gapFraction);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        startAngle, sweepAngle, false, paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashRingPainter old) => false;
}