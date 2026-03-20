// lib/screens/signup_screen.dart
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../services/security_service.dart';
import '../services/database_service.dart';
import '../models/employee.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  /// If coming from LoginScreen after an unknown NFC tap, this is pre-filled
  final String? prefilledNfcTag;

  const SignupScreen({super.key, this.prefilledNfcTag});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController     = TextEditingController();
  final _emailController    = TextEditingController();
  final _empIdController    = TextEditingController();
  final _roleController     = TextEditingController();
  final _passwordController = TextEditingController();

  bool    _isLoading      = false;
  bool    _nfcAvailable   = false;
  bool    _nfcScanning    = false;
  String? _scannedNfcTag;   // stores the hex tag ID
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill NFC tag if passed from LoginScreen
    if (widget.prefilledNfcTag != null) {
      _scannedNfcTag = widget.prefilledNfcTag;
    }
    _checkNfc();
  }

  Future<void> _checkNfc() async {
    final available = await NfcManager.instance.isAvailable();
    if (mounted) setState(() => _nfcAvailable = available);
  }

  // ─── NFC Scan for registration ────────────────────────────────────────────
  Future<void> _scanNfcTag() async {
    if (!_nfcAvailable || _nfcScanning) return;
    setState(() {
      _nfcScanning = true;
      _scannedNfcTag = null;
      _error = null;
    });

    try {
      await NfcManager.instance.stopSession();

      NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        onDiscovered: (NfcTag tag) async {
          final tagId = _extractTagId(tag);
          await NfcManager.instance.stopSession();

          if (tagId == null) {
            if (mounted) {
              setState(() {
                _error = 'Could not read tag ID. Try again.';
                _nfcScanning = false;
              });
            }
            return;
          }

          // Check if tag is already registered to another employee
          final existing =
          await DatabaseService.instance.getEmployeeByNfcTag(tagId);

          if (mounted) {
            if (existing != null) {
              setState(() {
                _error =
                'This keyfob is already registered to ${existing.fullName}.';
                _nfcScanning = false;
              });
            } else {
              setState(() {
                _scannedNfcTag = tagId;
                _nfcScanning   = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Keyfob registered: $tagId'),
                backgroundColor: AppColors.success,
                duration: const Duration(seconds: 2),
              ));
            }
          }
        },
      );

      // Auto-timeout after 20 s
      Future.delayed(const Duration(seconds: 20), () {
        if (mounted && _nfcScanning) {
          NfcManager.instance.stopSession();
          setState(() {
            _nfcScanning = false;
            _error ??= 'NFC scan timed out. Tap the button to try again.';
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'NFC error: $e';
          _nfcScanning = false;
        });
      }
    }
  }

  String? _extractTagId(NfcTag tag) {
    try {
      final tagMap = tag.data as Map<String, dynamic>;
      List<int>? tryKey(String k) {
        final tech = tagMap[k] as Map<dynamic, dynamic>?;
        if (tech == null) return null;
        final raw = tech['identifier'];
        return raw is List ? raw.cast<int>() : null;
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

  // ─── Register ─────────────────────────────────────────────────────────────
  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isLoading = true; _error = null; });

    try {
      final fullName  = _nameController.text.trim();
      final names     = fullName.split(' ');
      final firstName = names.isNotEmpty ? names[0] : '';
      final lastName  = names.length > 1 ? names.sublist(1).join(' ') : 'User';
      final empId     = _empIdController.text.trim().toUpperCase();

      // Check duplicate employee ID
      final existing =
      await DatabaseService.instance.getEmployeeByEmployeeId(empId);
      if (existing != null) throw 'Employee ID "$empId" is already registered.';

      // Hash PIN
      final salt         = SecurityService.instance.generateSalt();
      final passwordHash = SecurityService.instance
          .hashPin(_passwordController.text.trim(), salt);

      final employee = Employee(
        id:           const Uuid().v4(),
        employeeId:   empId,
        firstName:    firstName,
        lastName:     lastName,
        email:        _emailController.text.trim().toLowerCase(),
        department:   'Corporate',
        position:     _roleController.text.trim(),
        pinHash:      passwordHash,
        pinSalt:      salt,
        nfcTagId:     _scannedNfcTag,   // ← attach scanned tag (nullable)
        createdAt:    DateTime.now(),
        updatedAt:    DateTime.now(),
      );

      await DatabaseService.instance.insertEmployee(employee);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Registration successful! Please login.'),
        backgroundColor: AppColors.success,
      ));
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _empIdController.dispose();
    _roleController.dispose();
    _passwordController.dispose();
    try { NfcManager.instance.stopSession(); } catch (_) {}
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientDark),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildHeader(),
                    const SizedBox(height: 32),
                    _buildTextField(_nameController,  'Full Name',           Icons.person_outline),
                    const SizedBox(height: 16),
                    _buildTextField(_emailController, 'Email Address',       Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 16),
                    _buildTextField(_empIdController, 'Employee ID',         Icons.badge_outlined,
                        textCapitalization: TextCapitalization.characters),
                    const SizedBox(height: 16),
                    _buildTextField(_roleController,  'Role in Company',     Icons.work_outline),
                    const SizedBox(height: 16),
                    _buildTextField(_passwordController, 'Password (4-digit PIN)',
                        Icons.lock_outline,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4),
                    const SizedBox(height: 20),

                    // ── NFC keyfob section ─────────────────────────────────
                    if (_nfcAvailable) _buildNfcSection(),

                    const SizedBox(height: 24),
                    if (_error != null) _buildError(),
                    _buildSignupButton(),
                    const SizedBox(height: 16),
                    _buildLoginLink(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(children: [
      Container(
        width: 64, height: 60,
        decoration: BoxDecoration(
          gradient: AppColors.gradientPrimary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.person_add_rounded,
            color: AppColors.primary, size: 30),
      ),
      const SizedBox(height: 16),
      const Text('Create Account',
          style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5)),
      const SizedBox(height: 8),
      const Text('Enter your details to register',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
    ]);
  }

  // ── NFC keyfob card ────────────────────────────────────────────────────────
  Widget _buildNfcSection() {
    final hasTag = _scannedNfcTag != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasTag
              ? AppColors.success.withValues(alpha: 0.5)
              : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              hasTag
                  ? Icons.contactless_rounded
                  : Icons.nfc_rounded,
              color: hasTag ? AppColors.success : AppColors.textMuted,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              hasTag ? 'Keyfob Linked ✓' : 'Link NFC Keyfob (Optional)',
              style: TextStyle(
                color: hasTag ? AppColors.success : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (hasTag) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _scannedNfcTag!,
                    style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),
                ),
                GestureDetector(
                  onTap: () =>
                      setState(() => _scannedNfcTag = null),
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.textMuted, size: 16),
                ),
              ]),
            ),
            const SizedBox(height: 8),
          ] else
            const Text(
              'Tap your keyfob to link it to this account.',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _nfcScanning ? null : _scanNfcTag,
              style: ElevatedButton.styleFrom(
                backgroundColor: hasTag
                    ? AppColors.success.withValues(alpha: 0.12)
                    : AppColors.accent.withValues(alpha: 0.12),
                foregroundColor:
                hasTag ? AppColors.success : AppColors.accent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: hasTag ? AppColors.success : AppColors.accent,
                    width: 1.2,
                  ),
                ),
              ),
              icon: _nfcScanning
                  ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(hasTag
                  ? Icons.refresh_rounded
                  : Icons.contactless_rounded,
                  size: 18),
              label: Text(
                _nfcScanning
                    ? 'Waiting for keyfob...'
                    : hasTag
                    ? 'Scan Different Keyfob'
                    : 'Scan Keyfob Now',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller,
      String label,
      IconData icon, {
        TextInputType? keyboardType,
        TextCapitalization textCapitalization = TextCapitalization.none,
        bool obscureText = false,
        int? maxLength,
      }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      maxLength: maxLength,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.textMuted),
          counterText: ''),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'Field is required';
        if (maxLength != null && value.length != maxLength)
          return 'Must be $maxLength digits';
        return null;
      },
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(_error!,
          style: const TextStyle(color: AppColors.error, fontSize: 12)),
    );
  }

  Widget _buildSignupButton() {
    return SizedBox(
      width: double.infinity, height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSignup,
        child: _isLoading
            ? const CircularProgressIndicator(color: AppColors.primary)
            : const Text('Register Now',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildLoginLink() {
    return TextButton(
      onPressed: () => Navigator.pop(context),
      child: RichText(
        text: const TextSpan(
          text: 'Already have an account? ',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          children: [
            TextSpan(
              text: 'Login',
              style: TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}