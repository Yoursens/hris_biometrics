// lib/screens/login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import '../theme/app_theme.dart';
import '../services/security_service.dart';
import '../services/database_service.dart';
import '../services/location_tracking_service.dart';
import '../models/employee.dart';
import 'main_screen.dart';
import 'signup_screen.dart';
import 'landing_screen.dart';

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
  String? _error;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;

  String _statusAction = '';
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 10).animate(
        CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));
    _checkCapabilities();
  }

  Future<void> _checkCapabilities() async {
    final nfcAvailable = await NfcManager.instance.isAvailable();
    if (mounted) {
      setState(() {
        _nfcAvailable = nfcAvailable;
      });
    }
    // Auto-start NFC listening as soon as screen loads
    if (nfcAvailable) _startNfcSession();
  }

  // ─── NFC Session ─────────────────────────────────────────────────────────
  Future<void> _startNfcSession() async {
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
          if (tagId == null) {
            _setError('Could not read tag ID.');
            return;
          }

          // Format timestamp
          final now = DateTime.now();
          final timeStr =
              '${now.hour}:${now.minute.toString().padLeft(2, '0')}';

          if (mounted) setState(() => _currentTime = timeStr);

          try {
            setState(() {
              _isLoading = true;
              _error = null;
            });

            final employee =
            await DatabaseService.instance.getEmployeeByNfcTag(tagId);

            if (employee != null) {
              // ── Known tag → login ──────────────────────────────────────
              if (mounted) {
                setState(() => _statusAction = 'LOGIN SUCCESS');
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Welcome, ${employee.fullName}!'),
                  backgroundColor: AppColors.success,
                  duration: const Duration(seconds: 1),
                ));
              }
              await NfcManager.instance.stopSession();
              await _openSession(employee.id);
            } else {
              // ── Unknown tag → prompt to register ──────────────────────
              await NfcManager.instance.stopSession();
              if (mounted) {
                setState(() {
                  _statusAction = 'UNREGISTERED TAG';
                  _isLoading = false;
                });
                _showRegisterTagDialog(tagId);
              }
            }
          } catch (e) {
            _setError('NFC login error: $e');
          }
        },
      );
    } catch (e) {
      debugPrint('NFC session error: $e');
    }
  }

  // ─── Extract Tag ID from any NFC tech ────────────────────────────────────
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

      final id = tryKey('nfca') ??
          tryKey('nfcb') ??
          tryKey('nfcf') ??
          tryKey('nfcv') ??
          tryKey('isodep') ??
          tryKey('mifare-classic') ??
          tryKey('mifare-ultralight');

      if (id == null || id.isEmpty) return null;

      return id
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();
    } catch (_) {
      return null;
    }
  }

  // ─── Dialog: register unknown NFC tag ────────────────────────────────────
  void _showRegisterTagDialog(String tagId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.contactless_rounded,
              color: AppColors.accent, size: 22),
          SizedBox(width: 8),
          Text('Unknown Keyfob',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.nfc_rounded,
                    color: AppColors.accentSecondary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tag ID: $tagId',
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            const Text(
              'This keyfob is not registered. Would you like to register it now?',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startNfcSession(); // resume listening
            },
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to signup
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const SignupScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Register Now',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _loginWithPin() async {
    if (_pinInput.length < 4) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Find employee by PIN only (iterating through all local employees)
      final List<Employee> allEmployees = await DatabaseService.instance.getAllEmployees();
      Employee? matchedEmployee;

      for (var emp in allEmployees) {
        final isValid = await SecurityService.instance.verifyPin(emp.id, _pinInput);
        if (isValid) {
          matchedEmployee = emp;
          break;
        }
      }

      if (matchedEmployee == null) {
        throw 'Invalid PIN. Please try again.';
      }

      await _openSession(matchedEmployee.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _pinInput = '';
        });
        _shakeController.forward(from: 0);
      }
    }
  }

  Future<void> _openSession(String employeeId) async {
    try {
      await SecurityService.instance.createSession(employeeId);
      LocationTrackingService.instance.startTracking(employeeId);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Session error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _error = msg;
        _isLoading = false;
        _pinInput = '';
      });
      _shakeController.forward(from: 0);
    }
  }

  void _onPinKey(String key) {
    if (_isLoading) return;
    setState(() => _error = null);
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
    try { NfcManager.instance.stopSession(); } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LandingScreen()));
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.gradientDark),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLogo(),
                    if (_statusAction.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildStatusBanner(),
                    ],
                    const SizedBox(height: 48),
                    if (_nfcAvailable) ...[
                      _buildNfcSection(),
                      const SizedBox(height: 32),
                      _buildDivider(),
                      const SizedBox(height: 32),
                    ],
                    const Text('Enter Access PIN',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    const SizedBox(height: 24),
                    _buildPinDots(),
                    const SizedBox(height: 48),
                    _buildPinPad(),
                    const SizedBox(height: 24),
                    _buildFeedback(),
                    const SizedBox(height: 32),
                    _buildSignupLink(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          gradient: AppColors.gradientPrimary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 25, offset: const Offset(0, 10))
          ],
        ),
        child: const Icon(Icons.shield_rounded, color: AppColors.primary, size: 40),
      ),
      const SizedBox(height: 24),
      const Text('Secure Access',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -1)),
    ]);
  }

  Widget _buildStatusBanner() {
    final isSuccess = _statusAction == 'LOGIN SUCCESS';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: (isSuccess ? AppColors.success : AppColors.error)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isSuccess ? AppColors.success : AppColors.error)
              .withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSuccess
                ? Icons.check_circle_rounded
                : Icons.contactless_rounded,
            color: isSuccess ? AppColors.success : AppColors.error,
            size: 22,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_statusAction,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isSuccess
                          ? AppColors.success
                          : AppColors.error)),
              if (_currentTime.isNotEmpty)
                Text('Time: $_currentTime',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNfcSection() {
    return GestureDetector(
      onTap: _isLoading ? null : _startNfcSession,
      child: Container(
        width: 120, height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.card,
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.5), width: 2),
          boxShadow: [
            BoxShadow(color: AppColors.accent.withValues(alpha: 0.2), blurRadius: 24, spreadRadius: 4)
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _isLoading
                ? const CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)
                : const Icon(Icons.contactless_rounded, color: AppColors.accent, size: 48),
            if (!_isLoading) ...[
              const SizedBox(height: 8),
              const Text('TAP KEYFOB', style: TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.w900)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Row(children: [
      Expanded(child: Divider(color: AppColors.cardBorder)),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: Text('OR',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      ),
      Expanded(child: Divider(color: AppColors.cardBorder)),
    ]);
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final filled = i < _pinInput.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 12),
          width: 20, height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppColors.accent : Colors.transparent,
            border: Border.all(color: filled ? AppColors.accent : AppColors.textMuted, width: 2.5),
          ),
        );
      }),
    );
  }

  Widget _buildPinPad() {
    const rows = [ ['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', 'del'] ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, childAspectRatio: 1.8, mainAxisSpacing: 16, crossAxisSpacing: 16),
      itemCount: 12,
      itemBuilder: (_, idx) {
        final key = rows[idx ~/ 3][idx % 3];
        if (key.isEmpty) return const SizedBox();
        return GestureDetector(
          onTap: () => _onPinKey(key),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder, width: 1.5),
            ),
            child: Center(
              child: key == 'del'
                  ? const Icon(Icons.backspace_outlined, color: AppColors.textSecondary, size: 24)
                  : Text(key, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeedback() {
    if (_isLoading) return const SizedBox(height: 30, child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 3)));
    if (_error != null) {
      return AnimatedBuilder(
        animation: _shakeAnim,
        builder: (_, child) => Transform.translate(
          offset: Offset(_shakeAnim.value * ((_shakeController.value * 10).round().isEven ? 1 : -1), 0),
          child: child,
        ),
        child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 14, fontWeight: FontWeight.w600)),
      );
    }
    return const SizedBox(height: 30);
  }

  Widget _buildSignupLink() {
    return TextButton(
      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
      child: RichText(
        text: const TextSpan(
          text: "Don't have an account? ",
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          children: [
            TextSpan(
              text: 'Register',
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
