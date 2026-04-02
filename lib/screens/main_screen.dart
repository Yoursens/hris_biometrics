// lib/screens/main_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'clock_screen.dart';
import 'attendance_history_screen.dart';
import 'employees_screen.dart';
import 'reports_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _menuOpen = false;
  late AnimationController _menuCtrl;
  late Animation<double> _menuAnim;

  void switchTab(int index) {
    if (mounted) {
      debugPrint('Switching to tab index: $index');
      setState(() {
        _currentIndex = index;
        _menuOpen = false;
      });
      _menuCtrl.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    _menuCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _menuAnim = CurvedAnimation(
      parent: _menuCtrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCirc,
    );
  }

  @override
  void dispose() {
    _menuCtrl.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _menuOpen = !_menuOpen;
      if (_menuOpen) {
        _menuCtrl.forward();
      } else {
        _menuCtrl.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          // 1. Content Layer
          IndexedStack(
            index: _currentIndex,
            children: [
              DashboardScreen(onTabSwitch: switchTab),
              const ClockScreen(),
              const AttendanceHistoryScreen(),
              const EmployeesScreen(),
              const ReportsScreen(),
              const ProfileScreen(),
            ],
          ),

          // 2. Dimmer Layer (Only when menu is open)
          if (_menuOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleMenu,
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.black.withOpacity(0.7)),
              ),
            ),

          // 3. Bottom Bar Background Layer
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomBarContainer(),
          ),

          // 4. Radial Menu Items Layer (Must be above Bottom Bar to be clickable)
          ..._buildRadialItems(),

          // 5. Center FAB Layer (On top of everything)
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 20,
            child: Center(child: _buildCenterButton()),
          ),
        ],
      ),
    );
  }

  // ─── Nav Items Data ────────────────────────────────────────────────────────
  static const _navItems = [
    _NavData(icon: Icons.dashboard_rounded,   label: 'Home',      index: 0, color: Color(0xFF6C63FF)),
    _NavData(icon: Icons.fingerprint_rounded, label: 'Clock',     index: 1, color: Color(0xFF00D4AA)),
    _NavData(icon: Icons.history_rounded,     label: 'History',   index: 2, color: Color(0xFF4FC3F7)),
    _NavData(icon: Icons.people_rounded,      label: 'Employees', index: 3, color: Color(0xFF81C784)),
    _NavData(icon: Icons.bar_chart_rounded,   label: 'Reports',   index: 4, color: Color(0xFFFFB74D)),
    _NavData(icon: Icons.person_rounded,      label: 'Profile',   index: 5, color: Color(0xFFFF8A65)),
  ];

  Widget _buildBottomBarContainer() {
    final current = _navItems[_currentIndex];
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 70 + bottomPadding,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: const Border(
          top: BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left side label
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current.label,
                    style: TextStyle(
                      color: current.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'Current Page',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                  ),
                ],
              ),

              // Right side grid toggle
              GestureDetector(
                onTap: _toggleMenu,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      _menuOpen ? Icons.close_rounded : Icons.grid_view_rounded,
                      color: AppColors.textMuted,
                      size: 24,
                      key: ValueKey(_menuOpen),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterButton() {
    final current = _navItems[_currentIndex];
    return GestureDetector(
      onTap: _toggleMenu,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          gradient: _menuOpen
              ? const LinearGradient(colors: [Color(0xFFFF6B6B), Color(0xFFFF8E8E)])
              : AppColors.gradientPrimary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (_menuOpen ? const Color(0xFFFF6B6B) : AppColors.accent).withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: AnimatedRotation(
          turns: _menuOpen ? 0.125 : 0,
          duration: const Duration(milliseconds: 300),
          child: Icon(
            _menuOpen ? Icons.add : current.icon,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRadialItems() {
    // Relative coordinates for items when expanded (Positive Y is UP)
    const arcPositions = [
      Offset(-130, 30),   // Home
      Offset(-90, 100),   // Clock
      Offset(-30, 150),   // History
      Offset(30, 150),    // Employees
      Offset(90, 100),    // Reports
      Offset(130, 30),    // Profile
    ];

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenWidth = MediaQuery.of(context).size.width;

    return _navItems.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      final isSelected = _currentIndex == item.index;

      return AnimatedBuilder(
        animation: _menuAnim,
        builder: (context, child) {
          final t = _menuAnim.value;
          if (t == 0 && !_menuOpen) return const SizedBox.shrink();

          final offset = arcPositions[i];

          return Positioned(
            // Start from the center of the FAB and move UP
            bottom: bottomPadding + 50 + (offset.dy * t),
            left: (screenWidth / 2) - 25 + (offset.dx * t),
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: GestureDetector(
                onTap: () => switchTab(item.index),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (t > 0.8)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item.label,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isSelected ? item.color : AppColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: item.color, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: item.color.withOpacity(0.4),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        item.icon,
                        color: isSelected ? Colors.white : item.color,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }).toList();
  }
}

class _NavData {
  final IconData icon;
  final String   label;
  final int      index;
  final Color    color;

  const _NavData({
    required this.icon,
    required this.label,
    required this.index,
    required this.color,
  });
}
