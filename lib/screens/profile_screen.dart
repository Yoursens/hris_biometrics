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
    
    // Use passed-in employee as fallback (especially for Web)
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 10),
            Text('Delete Account', style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: const Text(
          'Are you sure you want to permanently delete your account? This action will remove all your data from the local database, cloud storage, and admin records. This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete Permanently', style: TextStyle(color: Colors.white)),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting account: $e'), backgroundColor: AppColors.error),
          );
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

    if (_loading || _isDeleting) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: cs.primary),
                if (_isDeleting) ...[
                  const SizedBox(height: 20),
                  const Text('Deleting account data...', style: TextStyle(color: AppColors.textSecondary)),
                ]
              ],
            )),
      );
    }

    final themeNotifier = context.watch<ThemeNotifier>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileCard(theme, cs, isDark),
              const SizedBox(height: 30),
              
              const Text('PREFERENCES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: AppColors.textMuted)),
              const SizedBox(height: 10),
              _buildSettings(theme, cs, themeNotifier),
              const SizedBox(height: 24),

              const Text('ACCOUNT SECURITY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: AppColors.textMuted)),
              const SizedBox(height: 10),
              _buildBiometricStatus(theme, cs),
              const SizedBox(height: 24),
              
              const Text('DATA & BACKUP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: AppColors.textMuted)),
              const SizedBox(height: 10),
              _buildSyncSection(theme, cs),
              const SizedBox(height: 24),

              const Text('DANGER ZONE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: AppColors.error)),
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
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 4),
                Text(
                  _employee?.email ?? '',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 12),
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
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_sync_rounded, color: AppColors.accent),
            title: const Text('Cloud Backup'),
            subtitle: const Text('Sync your profile to Firebase', style: TextStyle(fontSize: 12)),
            trailing: _isSyncing 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
              : const Icon(Icons.chevron_right),
            onTap: _isSyncing ? null : _syncToFirebase,
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricStatus(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
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
          Divider(color: theme.dividerColor, indent: 60),
          _BiometricRow(
            icon: Icons.fingerprint,
            label: 'Fingerprint Setup',
            enrolled: _employee?.hasFingerprintEnrolled ?? false,
            onEnroll: () => _enroll('Fingerprint'),
            onUnenroll: () => _unenroll('Fingerprint'),
          ),
          Divider(color: theme.dividerColor, indent: 60),
          _SettingTile(
            icon: Icons.history,
            label: 'Attendance History',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AttendanceHistoryScreen(initialEmployee: _employee)),
            ),
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
        icon: Icons.dark_mode_outlined,
        label: 'App Theme',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(themeNotifier.isDark ? 'Dark' : 'Light', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
            const SizedBox(width: 8),
            Switch(
              value: themeNotifier.isDark,
              onChanged: (_) => themeNotifier.toggle(),
              activeColor: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZone(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
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

  Widget _buildLogout() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout),
        label: const Text('LOG OUT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.error,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.2)),
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
      leading: Icon(
        icon,
        color: enrolled ? AppColors.success : cs.onSurface.withValues(alpha: 0.4),
      ),
      title: Text(
        label,
        style: TextStyle(
            color: cs.onSurface, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        enrolled ? 'Enabled' : 'Not configured',
        style: TextStyle(
          color: enrolled
              ? AppColors.success
              : cs.onSurface.withValues(alpha: 0.4),
          fontSize: 11,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: enrolled ? AppColors.error.withValues(alpha: 0.1) : AppColors.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap: enrolled ? onUnenroll : onEnroll,
          child: Text(
            enrolled ? 'Disable' : 'Set Up',
            style: TextStyle(
              color: enrolled ? AppColors.error : AppColors.accent,
              fontWeight: FontWeight.bold,
              fontSize: 12,
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
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: iconColor ?? cs.onSurface.withValues(alpha: 0.6)),
      title: Text(label, style: TextStyle(color: labelColor ?? cs.onSurface, fontWeight: FontWeight.w500)),
      trailing: trailing ??
          Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: 0.3), size: 18),
      onTap: onTap,
    );
  }
}
