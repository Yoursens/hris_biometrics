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
  final Employee? initialEmployee;
  const ProfileScreen({super.key, this.initialEmployee});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Employee? _employee;
  bool _loading = true;
  bool _isSyncing = false;
  bool _isDeleting = false;
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final empId = await SecurityService.instance.getCurrentEmployeeId();
    Employee? employee;
    if (empId != null) {
      employee = await DatabaseService.instance.getEmployeeById(empId);
    }
    employee ??= widget.initialEmployee;
    if (mounted) {
      setState(() {
        _employee = employee;
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await AuthService.instance.signOut(employee: _employee);
    await SecurityService.instance.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LandingScreen()),
          (_) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    if (_employee == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error),
          SizedBox(width: 10),
          Text('Delete Account',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900)),
        ]),
        content: const Text(
          'Are you sure you want to permanently delete your account? '
              'This will remove all your data from the local database, '
              'cloud storage, and admin records. This cannot be undone.',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4))),
            child: const Text('Delete Permanently',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isDeleting = true);
      try {
        await AuthService.instance.deleteAccount(_employee!);
        await SecurityService.instance.clearSession();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LandingScreen()),
                (_) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: AppColors.error,
          ));
        }
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
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
          await AuthService.instance
              .login(email: email, password: password);
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Profile successfully backed up to Cloud!'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: AppColors.error,
        ));
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
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Link Cloud Account',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your 4-digit PIN to secure your cloud backup.',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28,
                  letterSpacing: 10,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900),
              onChanged: (v) => pinInput = v,
              decoration: const InputDecoration(
                hintText: '––––',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, pinInput),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4))),
            child: const Text('CONFIRM',
                style: TextStyle(
                    fontWeight: FontWeight.w800, letterSpacing: 1)),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Biometrics not available.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    try {
      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan to enroll $type',
        options: const AuthenticationOptions(
            biometricOnly: true, stickyAuth: true),
      );
      if (authenticated) {
        await _updateBiometricFlag(type, enrolled: true);
        final updated =
        await DatabaseService.instance.getEmployeeById(_employee!.id);
        if (mounted) {
          setState(() => _employee = updated);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$type enrolled successfully'),
            backgroundColor: AppColors.success,
          ));
        }
      }
    } catch (e) {
      debugPrint('Enrollment error: $e');
    }
  }

  Future<void> _unenroll(String type) async {
    if (_employee == null) return;
    await _updateBiometricFlag(type, enrolled: false);
    final updated =
    await DatabaseService.instance.getEmployeeById(_employee!.id);
    if (mounted) {
      setState(() => _employee = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$type removed'),
        backgroundColor: AppColors.warning,
      ));
    }
  }

  Future<void> _updateBiometricFlag(String type,
      {required bool enrolled}) async {
    final emp = _employee;
    if (emp == null) return;
    final Employee updatedEmployee;
    if (type == 'Face ID') {
      updatedEmployee =
          emp.copyWith(faceEmbedding: enrolled ? emp.faceEmbedding : null);
    } else if (type == 'Fingerprint') {
      updatedEmployee = emp.copyWith(
          fingerprintHash: enrolled ? emp.fingerprintHash : null);
    } else {
      return;
    }
    await DatabaseService.instance.updateEmployee(updatedEmployee);
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading || _isDeleting) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: AppColors.orange),
            if (_isDeleting) ...[
              const SizedBox(height: 20),
              const Text('Deleting account data...',
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileCard(theme, cs),
              const SizedBox(height: 32),

              _sectionLabel('PREFERENCES'),
              const SizedBox(height: 10),
              Builder(
                builder: (ctx) {
                  final themeNotifier = ctx.watch<ThemeNotifier>();
                  return _buildSettings(theme, cs, themeNotifier);
                },
              ),
              const SizedBox(height: 28),

              _sectionLabel('ACCOUNT SECURITY'),
              const SizedBox(height: 10),
              _buildBiometricStatus(theme, cs),
              const SizedBox(height: 28),

              _sectionLabel('DATA & BACKUP'),
              const SizedBox(height: 10),
              _buildSyncSection(theme, cs),
              const SizedBox(height: 28),

              _sectionLabel('DANGER ZONE', color: AppColors.error),
              const SizedBox(height: 10),
              _buildDangerZone(theme, cs),

              const SizedBox(height: 40),
              _buildLogout(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, {Color color = AppColors.textMuted}) {
    return Text(text,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: color));
  }

  // ── Profile card ─────────────────────────────────────────────────────────────
  Widget _buildProfileCard(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppColors.orange.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
              color: AppColors.orange.withOpacity(0.08),
              blurRadius: 24,
              spreadRadius: 2),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: AppColors.gradientPrimary,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                    color: AppColors.orange.withOpacity(0.4),
                    blurRadius: 20),
              ],
            ),
            child: Center(
              child: Text(
                _employee?.initials ?? '??',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _employee?.fullName ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _employee?.position ?? 'Position',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  _employee?.email ?? '',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          // Status dot
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(3),
              border:
              Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: const Text('ACTIVE',
                style: TextStyle(
                    fontSize: 9,
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
          ),
        ],
      ),
    );
  }

  // ── Settings ─────────────────────────────────────────────────────────────────
  Widget _buildSettings(
      ThemeData theme, ColorScheme cs, ThemeNotifier themeNotifier) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: _SettingTile(
        icon: Icons.dark_mode_outlined,
        label: 'App Theme',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              themeNotifier.isDark ? 'Dark' : 'Light',
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Switch(
              value: themeNotifier.isDark,
              onChanged: (_) => themeNotifier.toggle(),
              activeColor: AppColors.orange,
            ),
          ],
        ),
      ),
    );
  }

  // ── Sync section ─────────────────────────────────────────────────────────────
  Widget _buildSyncSection(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: ListTile(
        leading: const Icon(Icons.cloud_sync_rounded,
            color: AppColors.orange),
        title: const Text('Cloud Backup',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700)),
        subtitle: const Text('Sync your profile to Firebase',
            style: TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
        trailing: _isSyncing
            ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.orange))
            : const Icon(Icons.chevron_right,
            color: AppColors.textMuted, size: 18),
        onTap: _isSyncing ? null : _syncToFirebase,
      ),
    );
  }

  // ── Biometric status ─────────────────────────────────────────────────────────
  Widget _buildBiometricStatus(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          _BiometricRow(
            icon: Icons.face,
            label: 'Face ID Setup',
            enrolled: _employee?.hasFaceEnrolled ?? false,
            onEnroll: () => _enroll('Face ID'),
            onUnenroll: () => _unenroll('Face ID'),
          ),
          Divider(
              color: AppColors.cardBorder, height: 1, indent: 56),
          _BiometricRow(
            icon: Icons.fingerprint,
            label: 'Fingerprint Setup',
            enrolled: _employee?.hasFingerprintEnrolled ?? false,
            onEnroll: () => _enroll('Fingerprint'),
            onUnenroll: () => _unenroll('Fingerprint'),
          ),
          Divider(
              color: AppColors.cardBorder, height: 1, indent: 56),
          _SettingTile(
            icon: Icons.history,
            label: 'Attendance History',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AttendanceHistoryScreen(
                    initialEmployee: _employee),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Danger zone ───────────────────────────────────────────────────────────────
  Widget _buildDangerZone(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: _SettingTile(
        icon: Icons.delete_forever_rounded,
        label: 'Delete My Account',
        labelColor: AppColors.error,
        iconColor: AppColors.error,
        onTap: _confirmDeleteAccount,
      ),
    );
  }

  // ── Logout ───────────────────────────────────────────────────────────────────
  Widget _buildLogout() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout_rounded,
            color: AppColors.error, size: 18),
        label: const Text('LOG OUT',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: AppColors.error,
                fontSize: 13)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4)),
          side: BorderSide(
              color: AppColors.error.withOpacity(0.3), width: 1),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Reusable widgets
// ══════════════════════════════════════════════════════════════════════════════

class _BiometricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enrolled;
  final VoidCallback onEnroll;
  final VoidCallback onUnenroll;

  const _BiometricRow({
    required this.icon,
    required this.label,
    required this.enrolled,
    required this.onEnroll,
    required this.onUnenroll,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: enrolled ? AppColors.success : AppColors.textMuted,
        size: 22,
      ),
      title: Text(
        label,
        style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14),
      ),
      subtitle: Text(
        enrolled ? 'Enabled' : 'Not configured',
        style: TextStyle(
          color: enrolled ? AppColors.success : AppColors.textMuted,
          fontSize: 11,
        ),
      ),
      trailing: GestureDetector(
        onTap: enrolled ? onUnenroll : onEnroll,
        child: Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: enrolled
                ? AppColors.error.withOpacity(0.08)
                : AppColors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: enrolled
                  ? AppColors.error.withOpacity(0.3)
                  : AppColors.orange.withOpacity(0.3),
            ),
          ),
          child: Text(
            enrolled ? 'DISABLE' : 'SET UP',
            style: TextStyle(
              color: enrolled ? AppColors.error : AppColors.orange,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 1,
            ),
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
  final Color? labelColor;
  final Color? iconColor;

  const _SettingTile({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.labelColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: iconColor ?? AppColors.textSecondary, size: 20),
      title: Text(label,
          style: TextStyle(
              color: labelColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14)),
      trailing: trailing ??
          const Icon(Icons.chevron_right,
              color: AppColors.textMuted, size: 18),
      onTap: onTap,
    );
  }
}