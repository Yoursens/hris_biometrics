// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/auth_service.dart';
import '../models/employee.dart';
import 'landing_screen.dart';
import 'attendance_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Employee? _employee;
  bool _loading = true;
  bool _isSyncing = false;
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final empId =
        await SecurityService.instance.getCurrentEmployeeId() ?? 'emp_001';
    final employee = await DatabaseService.instance.getEmployeeById(empId);
    if (mounted) {
      setState(() {
        _employee = employee;
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await AuthService.instance.signOut();
    await SecurityService.instance.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LandingScreen()),
          (_) => false,
    );
  }

  Future<void> _syncToFirebase() async {
    if (_employee == null || _isSyncing) return;
    
    setState(() => _isSyncing = true);
    
    try {
      User? user = AuthService.instance.currentUser;
      
      if (user == null) {
        final pin = await _promptForPin();
        if (pin == null || pin.length < 4) {
          throw 'Valid 4-digit PIN required to link cloud account';
        }

        final email = _employee!.email;
        final password = pin.padRight(6, '0');

        try {
          await AuthService.instance.login(email: email, password: password);
        } catch (e) {
          await AuthService.instance.registerEmployee(
            email: email,
            password: password,
            employee: _employee!,
          );
        }
        user = AuthService.instance.currentUser;
      }

      if (user == null) throw 'Could not authenticate with Firebase';

      final data = _employee!.toMap();
      data['uid'] = user.uid;
      data['last_manual_sync'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Profile successfully backed up to Cloud!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<String?> _promptForPin() async {
    String pinInput = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Link Cloud Account', 
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your 4-digit PIN to secure your cloud backup.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8, color: AppColors.textPrimary),
              onChanged: (v) => pinInput = v,
              decoration: const InputDecoration(
                hintText: 'PIN',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, pinInput),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _enroll(String type) async {
    if (_employee == null) return;
    bool canCheck = await _localAuth.canCheckBiometrics ||
        await _localAuth.isDeviceSupported();
    if (!canCheck) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometrics not available.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    try {
      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan to enroll $type',
        options:
        const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (authenticated) {
        await _updateBiometricFlag(type, enrolled: true);
        final updated =
        await DatabaseService.instance.getEmployeeById(_employee!.id);
        if (mounted) {
          setState(() => _employee = updated);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$type enrolled successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Enrollment error: $e");
    }
  }

  Future<void> _unenroll(String type) async {
    if (_employee == null) return;
    await _updateBiometricFlag(type, enrolled: false);
    final updated =
    await DatabaseService.instance.getEmployeeById(_employee!.id);
    if (mounted) {
      setState(() => _employee = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$type removed'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Future<void> _updateBiometricFlag(String type,
      {required bool enrolled}) async {
    final emp = _employee;
    if (emp == null) return;
    final Employee updatedEmployee;
    if (type == 'Face ID') {
      updatedEmployee = emp.copyWith(
        faceEmbedding: enrolled ? emp.faceEmbedding : null,
      );
    } else if (type == 'Fingerprint') {
      updatedEmployee = emp.copyWith(
        fingerprintHash: enrolled ? emp.fingerprintHash : null,
      );
    } else {
      return;
    }
    await DatabaseService.instance.updateEmployee(updatedEmployee);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
            child: CircularProgressIndicator(color: cs.primary)),
      );
    }

    final themeNotifier = context.watch<ThemeNotifier>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120), // Added bottom padding for navbar clearance
          child: Column(
            children: [
              _buildProfileCard(theme, cs, isDark),
              const SizedBox(height: 20),
              
              _buildSyncSection(theme, cs),
              const SizedBox(height: 20),

              _buildBiometricStatus(theme, cs),
              const SizedBox(height: 20),
              _buildSettings(theme, cs, themeNotifier),
              const SizedBox(height: 20),
              _buildSecuritySection(theme, cs),
              const SizedBox(height: 20),
              _buildLogout(),
              // Additional safety space
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(
      ThemeData theme, ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              gradient: AppColors.gradientPrimary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _employee?.initials ?? '??',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _employee?.fullName ?? 'Unknown',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  _employee?.position ?? 'Position',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                ),
                const SizedBox(height: 4),
                Text(
                  _employee?.email ?? '',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSection(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_sync_rounded, color: AppColors.accent, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cloud Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('Backup your profile to Firebase', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _isSyncing ? null : _syncToFirebase,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _isSyncing 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Sync Now', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricStatus(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          _BiometricRow(
            icon: Icons.face,
            label: 'Face ID',
            enrolled: _employee?.hasFaceEnrolled ?? false,
            onEnroll: () => _enroll('Face ID'),
            onUnenroll: () => _unenroll('Face ID'),
          ),
          Divider(color: theme.dividerColor),
          _BiometricRow(
            icon: Icons.fingerprint,
            label: 'Fingerprint',
            enrolled: _employee?.hasFingerprintEnrolled ?? false,
            onEnroll: () => _enroll('Fingerprint'),
            onUnenroll: () => _unenroll('Fingerprint'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings(
      ThemeData theme, ColorScheme cs, ThemeNotifier themeNotifier) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: _SettingTile(
        icon: Icons.dark_mode,
        label: 'Dark Mode',
        trailing: Switch(
          value: themeNotifier.isDark,
          onChanged: (_) => themeNotifier.toggle(),
          activeColor: AppColors.accent,
        ),
      ),
    );
  }

  Widget _buildSecuritySection(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: _SettingTile(
        icon: Icons.history,
        label: 'Attendance History',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AttendanceHistoryScreen()),
        ),
      ),
    );
  }

  Widget _buildLogout() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout),
        label: const Text('Logout Account'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error.withOpacity(0.1),
          foregroundColor: AppColors.error,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: AppColors.error.withOpacity(0.2)),
          elevation: 0,
        ),
      ),
    );
  }
}

class _BiometricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enrolled;
  final VoidCallback onEnroll, onUnenroll;

  const _BiometricRow({
    required this.icon,
    required this.label,
    required this.enrolled,
    required this.onEnroll,
    required this.onUnenroll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        color: enrolled ? AppColors.success : cs.onSurface.withOpacity(0.4),
      ),
      title: Text(
        label,
        style: TextStyle(
            color: cs.onSurface, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        enrolled ? 'Enrolled' : 'Not setup',
        style: TextStyle(
          color: enrolled
              ? AppColors.success
              : cs.onSurface.withOpacity(0.4),
          fontSize: 12,
        ),
      ),
      trailing: TextButton(
        onPressed: enrolled ? onUnenroll : onEnroll,
        child: Text(
          enrolled ? 'Remove' : 'Setup',
          style: TextStyle(
            color: enrolled ? AppColors.error : AppColors.accent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.onSurface.withOpacity(0.6)),
      title: Text(label, style: TextStyle(color: cs.onSurface)),
      trailing: trailing ??
          Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.4)),
      onTap: onTap,
    );
  }
}
