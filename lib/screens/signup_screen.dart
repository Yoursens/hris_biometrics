// lib/screens/signup_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:uuid/uuid.dart';
import 'package:local_auth/local_auth.dart';
import 'package:intl/intl.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';
import '../services/security_service.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/employee.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Step 1: Form Data
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _empIdController = TextEditingController();
  final _roleController = TextEditingController();
  final _pinController = TextEditingController();

  // Step 2: Fingerprint
  bool? _hasFingerprintChoice; // true = Yes, false = No
  bool _fingerprintDone = false;
  final LocalAuthentication _localAuth = LocalAuthentication();

  // Step 3: Face ID
  bool _faceIdDone = false;
  DateTime? _faceIdTimestamp;
  CameraController? _cameraController;
  bool _isCameraReady = false;

  // Step 4: NFC
  bool _nfcSupported = false;
  bool? _hasNfcChoice; // true = Yes, false = No
  String? _scannedNfcTag;
  bool _nfcScanning = false;

  bool _isRegistering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkNfcHardware();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _empIdController.dispose();
    _roleController.dispose();
    _pinController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkNfcHardware() async {
    try {
      bool isAvailable = await NfcManager.instance.isAvailable();
      if (mounted) setState(() => _nfcSupported = isAvailable);
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  void _nextPage() {
    if (_currentStep < 4) {
      if (_currentStep == 1) { // Moving from Fingerprint to Face ID
        _initCamera();
      }
      _pageController.nextPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      setState(() => _currentStep++);
    }
  }

  void _prevPage() {
    if (_currentStep > 0) {
      if (_currentStep == 2) { // Leaving Face ID step
        _cameraController?.dispose();
        _isCameraReady = false;
      }
      _pageController.previousPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      setState(() => _currentStep--);
    }
  }

  // --- Step 2: Fingerprint Enrollment ---
  Future<void> _enrollFingerprint() async {
    try {
      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan your fingerprint to link it to your account',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (authenticated && mounted) {
        setState(() => _fingerprintDone = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Fingerprint Linked'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      debugPrint('Fingerprint error: $e');
    }
  }

  // --- Step 3: Face ID Enrollment ---
  Future<void> _enrollFaceId() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      await _cameraController!.takePicture();
      setState(() {
        _faceIdDone = true;
        _faceIdTimestamp = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✓ Facial Recognition Captured'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      debugPrint('Take picture error: $e');
    }
  }

  // --- Step 4: NFC Logic ---
  Future<void> _scanNfc() async {
    if (_nfcScanning) return;
    setState(() { _nfcScanning = true; _scannedNfcTag = null; });

    try {
      NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
        final tagId = _extractTagId(tag);
        await NfcManager.instance.stopSession();
        if (mounted) {
          setState(() {
            _scannedNfcTag = tagId;
            _nfcScanning = false;
          });
        }
      });
    } catch (e) {
      if (mounted) setState(() => _nfcScanning = false);
    }
  }

  String? _extractTagId(NfcTag tag) {
    try {
      final tagMap = tag.data as Map;
      for (final value in tagMap.values) {
        if (value is Map && value.containsKey('identifier')) {
          final id = value['identifier'] as List<int>;
          return id.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
        }
      }
    } catch (_) {}
    return null;
  }

  // --- FINAL: Complete Registration ---
  Future<void> _handleFinalRegister() async {
    setState(() { _isRegistering = true; _error = null; });
    try {
      final fullName = _nameController.text.trim();
      final names = fullName.split(' ');
      final firstName = names.isNotEmpty ? names[0] : '';
      final lastName = names.length > 1 ? names.sublist(1).join(' ') : 'User';
      
      final salt = SecurityService.instance.generateSalt();
      final pinHash = SecurityService.instance.hashPin(_pinController.text.trim(), salt);

      final employee = Employee(
        id: const Uuid().v4(),
        employeeId: _empIdController.text.trim().toUpperCase(),
        firstName: firstName,
        lastName: lastName,
        email: _emailController.text.trim().toLowerCase(),
        department: 'Corporate',
        position: _roleController.text.trim(),
        pinHash: pinHash,
        pinSalt: salt,
        nfcTagId: _scannedNfcTag,
        faceEmbedding: _faceIdDone ? 'enrolled_data' : null,
        fingerprintHash: _fingerprintDone ? 'enrolled_data' : null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await AuthService.instance.registerEmployee(
        email: employee.email,
        password: _pinController.text.trim().padRight(6, '0'),
        employee: employee,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Registration successful!'),
        backgroundColor: AppColors.success,
      ));
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    } catch (e) {
      setState(() { _error = e.toString(); _isRegistering = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientDark),
        child: SafeArea(
          child: Column(
            children: [
              _buildProgressHeader(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStep1Form(),
                    _buildStep2Fingerprint(),
                    _buildStep3FaceId(),
                    _buildStep4Nfc(),
                    _buildStep5Summary(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) {
              bool active = i <= _currentStep;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: active ? AppColors.accent : Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            ['Account Info', 'Biometrics', 'Recognition', 'Keyfob', 'Review'][_currentStep],
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1Form() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const _StepHeader(title: 'Create Profile', subtitle: 'Enter your employment details'),
            const SizedBox(height: 32),
            _buildField(_nameController, 'Full Name', Icons.person_outline),
            const SizedBox(height: 16),
            _buildField(_empIdController, 'Employee ID', Icons.badge_outlined),
            const SizedBox(height: 16),
            _buildField(_emailController, 'Email Address', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),
            _buildField(_roleController, 'Role in Company', Icons.work_outline),
            const SizedBox(height: 16),
            _buildField(_pinController, '4-Digit PIN', Icons.lock_outline, maxLength: 4, keyboardType: TextInputType.number, obscureText: true),
            const SizedBox(height: 40),
            _buildNextButton(onPressed: () {
              if (_formKey.currentState!.validate()) _nextPage();
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Fingerprint() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const _StepHeader(title: 'Fingerprint', subtitle: 'Secure your account with biometrics'),
          const Spacer(),
          if (_hasFingerprintChoice == null) ...[
            const Icon(Icons.fingerprint_rounded, size: 80, color: Colors.white24),
            const SizedBox(height: 40),
            const Text('Do you want to use fingerprint login?', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _buildChoiceButton('YES', true, Icons.check_circle_outline, isFingerprint: true)),
                const SizedBox(width: 16),
                Expanded(child: _buildChoiceButton('NO', false, Icons.cancel_outlined, isFingerprint: true)),
              ],
            ),
          ] else if (_hasFingerprintChoice == true) ...[
            GestureDetector(
              onTap: _enrollFingerprint,
              child: Container(
                width: 150, height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _fingerprintDone ? AppColors.success.withOpacity(0.1) : AppColors.accent.withOpacity(0.1),
                  border: Border.all(color: _fingerprintDone ? AppColors.success : AppColors.accent, width: 2),
                ),
                child: Icon(
                  _fingerprintDone ? Icons.check_rounded : Icons.fingerprint_rounded,
                  size: 80,
                  color: _fingerprintDone ? AppColors.success : AppColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _fingerprintDone ? 'Fingerprint Linked Successfully' : 'Tap to scan your fingerprint',
              style: TextStyle(color: _fingerprintDone ? AppColors.success : Colors.white70),
            ),
            if (!_fingerprintDone)
              TextButton(onPressed: () => setState(() => _hasFingerprintChoice = false), child: const Text('Skip this step', style: TextStyle(color: Colors.white38))),
          ] else ...[
            const Icon(Icons.block_rounded, size: 80, color: Colors.white24),
            const SizedBox(height: 24),
            const Text('Fingerprint Scanning Skipped', style: TextStyle(color: Colors.white70)),
            TextButton(onPressed: () => setState(() => _hasFingerprintChoice = null), child: const Text('Change Choice', style: TextStyle(color: AppColors.accent))),
          ],
          const Spacer(),
          if (_fingerprintDone) ...[
            _buildReviewBox([
              _ReviewRow(label: 'Name', value: _nameController.text),
              _ReviewRow(label: 'ID', value: _empIdController.text),
              _ReviewRow(label: 'Role', value: _roleController.text),
            ]),
            const SizedBox(height: 24),
          ],
          Row(
            children: [
              Expanded(child: _buildBackButton()),
              const SizedBox(width: 16),
              Expanded(child: _buildNextButton(onPressed: (_hasFingerprintChoice == false || _fingerprintDone) ? _nextPage : null)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep3FaceId() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const _StepHeader(title: 'Facial Recognition', subtitle: 'Position your face in the center'),
          const Spacer(),
          Container(
            width: 240, height: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _faceIdDone ? AppColors.success : AppColors.accent, width: 2),
              color: Colors.black26,
            ),
            child: _faceIdDone 
              ? const Icon(Icons.face_rounded, size: 100, color: AppColors.success)
              : (_isCameraReady 
                  ? ClipRRect(borderRadius: BorderRadius.circular(18), child: CameraPreview(_cameraController!)) 
                  : const Center(child: CircularProgressIndicator())),
          ),
          const SizedBox(height: 24),
          if (_faceIdDone)
            Text('Captured at: ${DateFormat('hh:mm:ss a').format(_faceIdTimestamp!)}',
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (!_faceIdDone && _isCameraReady)
            _buildActionButton(
              label: 'Capture Face ID',
              onPressed: _enrollFaceId,
              icon: Icons.camera_alt_rounded,
            ),
          if (_faceIdDone)
            _buildActionButton(
              label: 'Capture Again',
              onPressed: () => setState(() => _faceIdDone = false),
              icon: Icons.refresh_rounded,
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildBackButton()),
              const SizedBox(width: 16),
              Expanded(child: _buildNextButton(onPressed: _faceIdDone ? _nextPage : null)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep4Nfc() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const _StepHeader(title: 'NFC Keyfob', subtitle: 'Do you want to link a physical keyfob?'),
          const Spacer(),
          if (_hasNfcChoice == null) ...[
            const Icon(Icons.contactless_rounded, size: 80, color: Colors.white24),
            const SizedBox(height: 40),
            const Text('Does your phone support NFC scanning?', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _buildChoiceButton('YES', true, Icons.check_circle_outline)),
                const SizedBox(width: 16),
                Expanded(child: _buildChoiceButton('NO', false, Icons.cancel_outlined)),
              ],
            ),
          ] else if (_hasNfcChoice == true) ...[
            GestureDetector(
              onTap: _scanNfc,
              child: Container(
                width: 150, height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _scannedNfcTag != null ? AppColors.success.withOpacity(0.1) : AppColors.accent.withOpacity(0.1),
                  border: Border.all(color: _scannedNfcTag != null ? AppColors.success : AppColors.accent, width: 2),
                ),
                child: Icon(
                  _nfcScanning ? Icons.sync_rounded : (_scannedNfcTag != null ? Icons.check_rounded : Icons.nfc_rounded),
                  size: 80,
                  color: _scannedNfcTag != null ? AppColors.success : AppColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _nfcScanning ? 'Scanning...' : (_scannedNfcTag != null ? 'Tag Linked: $_scannedNfcTag' : 'Tap to scan your Keyfob'),
              style: TextStyle(color: _scannedNfcTag != null ? AppColors.success : Colors.white70),
            ),
            if (_scannedNfcTag == null && !_nfcScanning) 
              TextButton(onPressed: () => setState(() => _hasNfcChoice = false), child: const Text('Skip this step', style: TextStyle(color: Colors.white38))),
          ] else ...[
            const Icon(Icons.block_rounded, size: 80, color: Colors.white24),
            const SizedBox(height: 24),
            const Text('NFC Scanning Skipped', style: TextStyle(color: Colors.white70)),
            TextButton(onPressed: () => setState(() => _hasNfcChoice = null), child: const Text('Change Choice', style: TextStyle(color: AppColors.accent))),
          ],
          const Spacer(),
          Row(
            children: [
              Expanded(child: _buildBackButton()),
              const SizedBox(width: 16),
              Expanded(child: _buildNextButton(onPressed: (_hasNfcChoice == false || _scannedNfcTag != null) ? _nextPage : null)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep5Summary() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const _StepHeader(title: 'Review Details', subtitle: 'Confirm your registration info'),
          const SizedBox(height: 24),
          _buildReviewBox([
            _ReviewRow(label: 'Full Name', value: _nameController.text),
            _ReviewRow(label: 'Employee ID', value: _empIdController.text),
            _ReviewRow(label: 'Email', value: _emailController.text),
            _ReviewRow(label: 'Role', value: _roleController.text),
            _ReviewRow(label: 'Fingerprint', value: _fingerprintDone ? '✓ Enrolled' : 'Not set', isSuccess: _fingerprintDone),
            _ReviewRow(label: 'Face ID', value: _faceIdDone ? '✓ Enrolled' : 'Not set', isSuccess: _faceIdDone),
            _ReviewRow(label: 'Keyfob Tag', value: _scannedNfcTag ?? 'Not linked'),
          ]),
          const SizedBox(height: 32),
          if (_error != null) 
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              onPressed: _isRegistering ? null : _handleFinalRegister,
              child: _isRegistering ? const CircularProgressIndicator() : const Text('Complete Registration', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          _buildBackButton(),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType, bool obscureText = false, int? maxLength}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.white38),
        counterText: '',
      ),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }

  Widget _buildNextButton({required VoidCallback? onPressed}) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.primary),
        child: const Text('Next Step', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildBackButton() {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: _prevPage,
        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
        child: const Text('Back', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildChoiceButton(String label, bool choice, IconData icon, {bool isFingerprint = false}) {
    return SizedBox(
      height: 60,
      child: ElevatedButton.icon(
        onPressed: () => setState(() {
          if (isFingerprint) {
            _hasFingerprintChoice = choice;
          } else {
            _hasNfcChoice = choice;
          }
        }),
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
      ),
    );
  }

  Widget _buildActionButton({required String label, required VoidCallback onPressed, required IconData icon}) {
    return SizedBox(
      width: double.infinity, height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildReviewBox(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(children: children),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final String title, subtitle;
  const _StepHeader({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 20),
      Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5)),
      const SizedBox(height: 8),
      Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 14)),
    ]);
  }
}

class _ReviewRow extends StatelessWidget {
  final String label, value;
  final bool isSuccess;
  const _ReviewRow({required this.label, required this.value, this.isSuccess = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
          Text(value, style: TextStyle(color: isSuccess ? AppColors.success : Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
