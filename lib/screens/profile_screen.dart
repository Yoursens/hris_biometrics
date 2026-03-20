// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
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
  bool _biometricEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final empId = await SecurityService.instance.getCurrentEmployeeId() ?? 'emp_001';
    final employee = await DatabaseService.instance.getEmployeeById(empId);
    if (mounted) setState(() {
      _employee = employee;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await SecurityService.instance.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LandingScreen()),
          (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildProfileCard(),
              const SizedBox(height: 20),
              _buildBiometricStatus(),
              const SizedBox(height: 20),
              _buildSettings(),
              const SizedBox(height: 20),
              _buildSecuritySection(),
              const SizedBox(height: 20),
              _buildLogout(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withOpacity(0.2),
            AppColors.accentSecondary.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.4),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(_employee?.initials ?? 'EM',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      )),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_employee?.fullName ?? 'Employee',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    )),
                const SizedBox(height: 4),
                Text(_employee?.position ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    )),
                const SizedBox(height: 4),
                Text(_employee?.employeeId ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricStatus() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.gradientCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Biometric Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              )),
          const SizedBox(height: 16),
          _BiometricRow(
            icon: Icons.face_retouching_natural,
            label: 'Face Recognition',
            enrolled: _employee?.hasFaceEnrolled ?? false,
            onEnroll: () => _showEnrollDialog('Face ID'),
          ),
          const Divider(color: AppColors.cardBorder, height: 24),
          _BiometricRow(
            icon: Icons.fingerprint_rounded,
            label: 'Fingerprint',
            enrolled: _employee?.hasFingerprintEnrolled ?? false,
            onEnroll: () => _showEnrollDialog('Fingerprint'),
          ),
          const Divider(color: AppColors.cardBorder, height: 24),
          _BiometricRow(
            icon: Icons.pin_rounded,
            label: 'PIN Code',
            enrolled: _employee?.hasPinSet ?? false,
            onEnroll: () => _showSetPinDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.gradientCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          _SettingTile(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            trailing: Switch(
              value: true,
              onChanged: (_) {},
              activeColor: AppColors.accent,
            ),
          ),
          const Divider(color: AppColors.cardBorder, height: 1),
          _SettingTile(
            icon: Icons.fingerprint_rounded,
            label: 'Biometric Login',
            trailing: Switch(
              value: _biometricEnabled,
              onChanged: (v) => setState(() => _biometricEnabled = v),
              activeColor: AppColors.accent,
            ),
          ),
          const Divider(color: AppColors.cardBorder, height: 1),
          _SettingTile(
            icon: Icons.location_on_outlined,
            label: 'Geo-fencing',
            trailing: Switch(
              value: true,
              onChanged: (_) {},
              activeColor: AppColors.accent,
            ),
          ),
          const Divider(color: AppColors.cardBorder, height: 1),
          _SettingTile(
            icon: Icons.dark_mode_rounded,
            label: 'Dark Mode',
            trailing: Switch(
              value: true,
              onChanged: (_) {},
              activeColor: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection() {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.gradientCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Security',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                )),
          ),
          _SettingTile(
            icon: Icons.calendar_month_rounded,
            label: 'My Attendance History',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AttendanceHistoryScreen())),
          ),
          const Divider(color: AppColors.cardBorder, height: 1),
          _SettingTile(
            icon: Icons.history_rounded,
            label: 'Audit Log',
            onTap: () {},
          ),
          const Divider(color: AppColors.cardBorder, height: 1),
          _SettingTile(
            icon: Icons.devices_rounded,
            label: 'Trusted Devices',
            onTap: () {},
          ),
          const Divider(color: AppColors.cardBorder, height: 1),
          _SettingTile(
            icon: Icons.lock_reset_rounded,
            label: 'Change PIN',
            onTap: _showSetPinDialog,
          ),
          const Divider(color: AppColors.cardBorder, height: 1),
          _SettingTile(
            icon: Icons.info_outline_rounded,
            label: 'App Version',
            trailing: const Text('v1.0.0',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildLogout() {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Sign Out',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          content: const Text('Are you sure you want to sign out?',
              style: TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
            TextButton(
                onPressed: _logout,
                child: const Text('Sign Out', style: TextStyle(color: AppColors.error))),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withOpacity(0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
            SizedBox(width: 10),
            Text('Sign Out',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                )),
          ],
        ),
      ),
    );
  }

  void _showEnrollDialog(String type) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Enroll $type',
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('Follow the prompts to enroll your $type biometric.',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Start')),
        ],
      ),
    );
  }

  void _showSetPinDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Set PIN',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text('Choose a 4-digit PIN for quick authentication.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Set PIN')),
        ],
      ),
    );
  }
}

class _BiometricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enrolled;
  final VoidCallback onEnroll;
  const _BiometricRow({required this.icon, required this.label,
    required this.enrolled, required this.onEnroll});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            color: enrolled ? AppColors.success : AppColors.textMuted, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
              Text(enrolled ? 'Enrolled ✓' : 'Not enrolled',
                  style: TextStyle(
                    fontSize: 12,
                    color: enrolled ? AppColors.success : AppColors.textMuted,
                  )),
            ],
          ),
        ),
        TextButton(
          onPressed: onEnroll,
          child: Text(enrolled ? 'Update' : 'Enroll',
              style: TextStyle(
                color: enrolled ? AppColors.textSecondary : AppColors.accent,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              )),
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingTile({required this.icon, required this.label, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(label,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          )),
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted)
              : null),
    );
  }
}