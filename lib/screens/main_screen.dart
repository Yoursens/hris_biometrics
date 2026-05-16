// lib/screens/main_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../theme/app_theme.dart';
import '../models/employee.dart' as model;
import 'dashboard_screen.dart';
import 'clock_screen.dart';
import 'attendance_history_screen.dart';
import 'employees_screen.dart';
import 'reports_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  final model.Employee? employee;
  const MainScreen({super.key, this.employee});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  void switchTab(int index) {
    if (mounted) setState(() => _currentIndex = index);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Nav items — all use orange palette tones ───────────────────────────────
  static const _navItems = [
    _NavData(icon: Icons.dashboard_rounded,   label: 'Dashboard',  index: 0, color: Color(0xFFFF5500)),
    _NavData(icon: Icons.fingerprint_rounded, label: 'Clock',      index: 1, color: Color(0xFFFF7A1A)),
    _NavData(icon: Icons.history_rounded,     label: 'History',    index: 2, color: Color(0xFFFFAA00)),
    _NavData(icon: Icons.people_rounded,      label: 'Employees',  index: 3, color: Color(0xFFFF3D00)),
    _NavData(icon: Icons.bar_chart_rounded,   label: 'Reports',    index: 4, color: Color(0xFFFFCC44)),
    _NavData(icon: Icons.person_rounded,      label: 'Profile',    index: 5, color: Color(0xFFFF8833)),
  ];

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb && MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Row(
        children: [
          if (isWeb) _buildWebSidebar(),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  bottom: isWeb ? 0 : 70,
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      DashboardScreen(
                          onTabSwitch: switchTab,
                          initialEmployee: widget.employee),
                      ClockScreen(initialEmployee: widget.employee),
                      AttendanceHistoryScreen(
                          initialEmployee: widget.employee),
                      const EmployeesScreen(),
                      ReportsScreen(initialEmployee: widget.employee),
                      ProfileScreen(initialEmployee: widget.employee),
                    ],
                  ),
                ),
                if (!isWeb)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildMobileBottomNav(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Web Sidebar ──────────────────────────────────────────────────────────────
  Widget _buildWebSidebar() {
    final w = MediaQuery.of(context).size.width;
    final sidebarWidth = w >= 1200 ? 260.0 : 220.0;

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          right: BorderSide(
              color: AppColors.orange.withOpacity(0.12), width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildWebLogo(),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children:
              _navItems.map((item) => _webNavItem(item)).toList(),
            ),
          ),
          _buildWebProfileFooter(),
        ],
      ),
    );
  }

  Widget _buildWebLogo() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AppColors.orange.withOpacity(0.12), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.gradientPrimary,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: AppColors.orange.withOpacity(0.35),
                  blurRadius: 14,
                )
              ],
            ),
            child: const Icon(Icons.fingerprint_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('HRIS',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3)),
              Text('BIOMETRICS',
                  style: TextStyle(
                      color: AppColors.orange,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _webNavItem(_NavData item) {
    final active = _currentIndex == item.index;
    return InkWell(
      onTap: () => switchTab(item.index),
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: active
              ? item.color.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active
                ? item.color.withOpacity(0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(item.icon,
                color: active
                    ? item.color
                    : AppColors.textMuted,
                size: 18),
            const SizedBox(width: 14),
            Text(
              item.label.toUpperCase(),
              style: TextStyle(
                color: active
                    ? AppColors.textPrimary
                    : AppColors.textMuted,
                fontWeight:
                active ? FontWeight.w800 : FontWeight.w500,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            if (active) ...[
              const Spacer(),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWebProfileFooter() {
    final emp = widget.employee;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: AppColors.orange.withOpacity(0.12), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppColors.gradientPrimary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                emp?.initials ?? '?',
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emp?.fullName ?? 'Guest',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  emp?.position ?? 'User',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.logout_rounded,
                color: AppColors.textMuted, size: 17),
          ),
        ],
      ),
    );
  }

  // ── Mobile Bottom Nav ────────────────────────────────────────────────────────
  Widget _buildMobileBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          top: BorderSide(
              color: AppColors.orange.withOpacity(0.2), width: 1),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 24,
              offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: _navItems.map((item) {
              final active = _currentIndex == item.index;
              return Expanded(
                child: GestureDetector(
                  onTap: () => switchTab(item.index),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: active
                              ? item.color.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(item.icon,
                            color: active
                                ? item.color
                                : AppColors.textMuted,
                            size: 19),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label.toUpperCase(),
                        style: TextStyle(
                          color: active
                              ? item.color
                              : AppColors.textMuted,
                          fontSize: 8,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w500,
                          letterSpacing: 0.8,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavData {
  final IconData icon;
  final String label;
  final int index;
  final Color color;

  const _NavData({
    required this.icon,
    required this.label,
    required this.index,
    required this.color,
  });
}