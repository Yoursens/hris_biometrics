// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fl_chart/fl_chart.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/geofence_service.dart';
import '../services/alarm_service.dart';
import '../data/local/dao/sync_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/employee.dart';
import '../models/attendance.dart';
import 'attendance_history_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design Tokens — fixed accent/status colors stay the same in both themes.
// Layout / spacing / radius constants are theme-independent.
// ─────────────────────────────────────────────────────────────────────────────
class _BS {
  // Grid
  static const double containerMaxWidth = 1320;
  static const double gutter   = 24.0;
  static const double gutterSm = 12.0;

  // Spacing
  static const double s0 = 0;
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 16;
  static const double s4 = 24;
  static const double s5 = 48;

  // Border radius
  static const double radiusSm   = 6;
  static const double radius     = 10;
  static const double radiusLg   = 16;
  static const double radiusXl   = 20;
  static const double radiusPill = 50;

  // ── Fixed accent / status palette (unchanged in both themes) ──────────────
  static const Color accent   = Color(0xFF00D4FF);
  static const Color success  = Color(0xFF00E5A0);
  static const Color warning  = Color(0xFFFFBB00);
  static const Color danger   = Color(0xFFFF4D6D);
  static const Color purple   = Color(0xFF9B6FFF);

  // ── Dark-mode surface palette (used as fallbacks in dark builds) ──────────
  static const Color navy      = Color(0xFF0A0F2E);
  static const Color navyLight = Color(0xFF131A45);
  static const Color navyCard  = Color(0xFF0F1535);
  static const Color white     = Color(0xFFFFFFFF);
  static const Color white70   = Color(0xB3FFFFFF);
  static const Color white40   = Color(0x66FFFFFF);
  static const Color white15   = Color(0x26FFFFFF);
  static const Color white08   = Color(0x14FFFFFF);

  // Typography
  static const double fs1 = 32;
  static const double fs2 = 26;
  static const double fs3 = 20;
  static const double fs4 = 16;
  static const double fs5 = 13;
  static const double fs6 = 11;

  static const FontWeight fwNormal = FontWeight.w400;
  static const FontWeight fwMedium = FontWeight.w500;
  static const FontWeight fwSemi   = FontWeight.w600;
  static const FontWeight fwBold   = FontWeight.w700;
  static const FontWeight fwBlack  = FontWeight.w900;

  // Shadows
  static List<BoxShadow> shadowSm(bool isDark) => [
    BoxShadow(
      color: isDark
          ? Colors.black.withOpacity(0.25)
          : Colors.black.withOpacity(0.07),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  // ── Theme-aware helpers ───────────────────────────────────────────────────
  static Color scaffoldBg(BuildContext ctx) =>
      Theme.of(ctx).scaffoldBackgroundColor;

  static Color cardBg(BuildContext ctx) => Theme.of(ctx).cardColor;

  static Color onSurface(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.onSurface;

  static Color onSurfaceFaint(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.onSurface.withOpacity(0.4);

  static Color dividerColor(BuildContext ctx) => Theme.of(ctx).dividerColor;

  static bool isDark(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark;

  /// Returns white-ish or dark-ish depending on theme
  static Color overlayBorder(BuildContext ctx) =>
      isDark(ctx) ? white15 : const Color(0xFFDDE8F0);

  static Color greetingCard(BuildContext ctx) =>
      isDark(ctx) ? navyLight : const Color(0xFFF4F8FF);

  static Color timeBlock(BuildContext ctx) =>
      isDark(ctx) ? navyCard : Colors.white;
}

// ─────────────────────────────────────────────────────────────────────────────
// Bootstrap-style helper widgets
// ─────────────────────────────────────────────────────────────────────────────

/// .badge
class _BsBadge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final bool pill;

  const _BsBadge({
    required this.text,
    required this.bg,
    this.fg = _BS.white,
    this.pill = true,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(
          pill ? _BS.radiusPill : _BS.radiusSm),
      border: Border.all(color: fg.withOpacity(0.2), width: 0.5),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: _BS.fs6,
        fontWeight: _BS.fwBold,
        color: fg,
        letterSpacing: 0.4,
      ),
    ),
  );
}

/// .card — theme-aware
class _BsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final List<BoxShadow>? boxShadow;
  final double? borderRadius;
  final Border? border;

  const _BsCard({
    required this.child,
    this.padding,
    this.color,
    this.boxShadow,
    this.borderRadius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _BS.isDark(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(_BS.s4),
      decoration: BoxDecoration(
        color: color ?? _BS.cardBg(context),
        borderRadius:
        BorderRadius.circular(borderRadius ?? _BS.radiusXl),
        border: border ??
            Border.all(
              color: _BS.overlayBorder(context),
              width: isDark ? 0.5 : 1,
            ),
        boxShadow: boxShadow ?? _BS.shadowSm(isDark),
      ),
      child: child,
    );
  }
}

/// .btn — theme-aware text only (colors passed explicitly)
class _BsBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final bool outline;
  final bool small;

  const _BsBtn({
    required this.label,
    required this.onTap,
    this.bg = _BS.accent,
    this.fg = _BS.white,
    this.icon,
    this.outline = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? _BS.s3 : _BS.s4,
        vertical: small ? _BS.s2 : 12,
      ),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : bg,
        borderRadius: BorderRadius.circular(_BS.radiusPill),
        border: Border.all(color: bg, width: 1.5),
        boxShadow:
        outline ? null : _BS.shadowSm(_BS.isDark(context)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, color: outline ? bg : fg,
              size: small ? 14 : 16),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: small ? _BS.fs6 : _BS.fs5,
            fontWeight: _BS.fwBold,
            color: outline ? bg : fg,
            letterSpacing: 0.3,
          ),
        ),
      ]),
    ),
  );
}

/// Bootstrap .row
class _BsRow extends StatelessWidget {
  final List<_BsCol> children;
  final double gutter;
  const _BsRow({required this.children, this.gutter = _BS.gutterSm});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children.asMap().entries.map((e) {
      final isLast = e.key == children.length - 1;
      return Expanded(
        flex: e.value.flex,
        child: Padding(
          padding: EdgeInsets.only(right: isLast ? 0 : gutter),
          child: e.value.child,
        ),
      );
    }).toList(),
  );
}

/// Bootstrap .col
class _BsCol {
  final Widget child;
  final int flex;
  const _BsCol({required this.child, this.flex = 1});
}

/// Bootstrap .list-group-item — theme-aware
class _BsListItem extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool isLast;

  const _BsListItem({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final textMain  = _BS.onSurface(context);
    final textFaint = _BS.onSurfaceFaint(context);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: textMain,
                        fontWeight: _BS.fwBold,
                        fontSize: _BS.fs5)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: textFaint, fontSize: _BS.fs6)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
      if (!isLast)
        Divider(
            color: _BS.dividerColor(context),
            thickness: 0.5,
            height: 0),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabSwitch;
  final Employee? initialEmployee;
  const DashboardScreen(
      {super.key, this.onTabSwitch, this.initialEmployee});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  Employee? _employee;
  Attendance? _todayAttendance;
  List<Attendance> _recent = [];
  Map<String, int> _stats = {};
  List<Map<String, dynamic>> _weekly = [];

  bool _loading = true;
  bool _isDemo = false;
  bool _needsVerification = true;
  int _pendingCount = 0;
  bool _isVerifying = false;
  bool _isShowingAlarmDialog = false;

  String? _spotCheckPhotoPath;
  DateTime? _spotCheckTime;

  StreamSubscription? _syncSub;
  StreamSubscription? _connectSub;
  StreamSubscription? _attendanceSub;
  late Timer _clock;
  DateTime _now = DateTime.now();
  String? _overriddenEmployeeId;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _fadeAnim =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(
            parent: _pulseController, curve: Curves.easeInOut));

    _clock = Timer.periodic(const Duration(seconds: 1),
            (_) { if (mounted) setState(() => _now = DateTime.now()); });

    _syncSub = SyncService.instance.events.listen((e) {
      if (!mounted) return;
      setState(() => _pendingCount = e.pendingCount);
      if (e.type == SyncEventType.syncDone) _loadData();
    });

    _connectSub =
        ConnectivityService.instance.onStatusChange.listen((on) {
          if (mounted && on) _loadData();
        });

    _attendanceSub =
        DatabaseService.instance.onAttendanceChanged.listen((empId) {
          if (mounted) {
            setState(() => _overriddenEmployeeId = empId);
            _loadData();
          }
        });

    _loadData();
  }

  @override
  void dispose() {
    _clock.cancel();
    _fadeController.dispose();
    _pulseController.dispose();
    _syncSub?.cancel();
    _connectSub?.cancel();
    _attendanceSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final loggedInId =
    await SecurityService.instance.getCurrentEmployeeId();
    final targetId = _overriddenEmployeeId ?? loggedInId;
    _isDemo = await SecurityService.instance.isDemoSession();

    Employee? emp;
    if (targetId != null && !kIsWeb) {
      emp = await DatabaseService.instance.getEmployeeById(targetId);
    }
    emp ??= widget.initialEmployee;

    if (emp == null && targetId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final idToQuery = targetId ?? emp?.id;
    Attendance? today;
    Map<String, int> stats = {};
    List<Map<String, dynamic>> weekly = [];
    List<Attendance> recent = [];
    int pending = 0;

    if (idToQuery != null && !kIsWeb) {
      today =
      await DatabaseService.instance.getTodayAttendance(idToQuery);
      stats =
      await DatabaseService.instance.getAttendanceStats(idToQuery);
      weekly = await DatabaseService.instance
          .getWeeklyWorkHours(idToQuery);
      recent = await DatabaseService.instance
          .getAttendanceByEmployee(idToQuery, limit: 5);
      pending = await SyncService.instance.getPendingCount();
    }

    if (mounted) {
      setState(() {
        _employee        = emp;
        _todayAttendance = today;
        _stats           = stats;
        _weekly          = weekly;
        _recent          = recent;
        _pendingCount    = pending;
        _loading         = false;
      });
    }
  }

  // ── Alarm ──────────────────────────────────────────────────────────────────
  Future<void> _checkAlarmConditions() async {
    if (_isShowingAlarmDialog || _loading) return;
    final now = DateTime.now();
    if (now.hour == 21 && now.minute >= 0 && now.minute < 30) {
      final isClockedIn = _todayAttendance?.isClockedIn ?? false;
      if (!isClockedIn) {
        final geoResult =
        await GeofenceService.instance.checkGeofence();
        if (!geoResult.isInside) _triggerAlarm();
      }
    }
  }

  void _triggerAlarm() {
    if (_isShowingAlarmDialog) return;
    setState(() => _isShowingAlarmDialog = true);
    AlarmService.instance.startAlarm();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _BS.cardBg(context),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_BS.radiusXl)),
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: _BS.danger.withOpacity(0.15),
                shape: BoxShape.circle),
            child: const Icon(Icons.warning_amber_rounded,
                color: _BS.danger, size: 20),
          ),
          const SizedBox(width: 12),
          Text('System Alert',
              style: TextStyle(
                  color: _BS.onSurface(context),
                  fontWeight: _BS.fwBlack,
                  fontSize: _BS.fs4)),
        ]),
        content: Text(
          'You are outside the work radius and have not timed in before 9:30 PM.',
          style: TextStyle(
              color: _BS.onSurface(context).withOpacity(0.7),
              fontSize: _BS.fs5,
              height: 1.5),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _BS.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(_BS.radius)),
                  padding:
                  const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () {
                AlarmService.instance.stopAlarm();
                FlutterBackgroundService()
                    .invoke('stop_alarm_from_ui');
                Navigator.of(context).pop();
                setState(() => _isShowingAlarmDialog = false);
              },
              child: const Text('STOP THE ALARM',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: _BS.fwBlack)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Spot-check ─────────────────────────────────────────────────────────────
  Future<void> _startLocationVerification() async {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first);
      if (!mounted) return;
      final String? photoPath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  _VerificationCameraScreen(camera: cam)));
      if (photoPath != null && mounted) {
        setState(() {
          _spotCheckPhotoPath = photoPath;
          _spotCheckTime      = DateTime.now();
          _needsVerification  = false;
        });
      }
    } catch (e) {
      debugPrint('Camera error: $e');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _openHistory() {
    if (widget.onTabSwitch != null) {
      widget.onTabSwitch!.call(2);
    } else {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AttendanceHistoryScreen()))
          .then((_) => _loadData());
    }
  }

  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try {
      return DateFormat('hh:mm a')
          .format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) {
      return t;
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bgColor = _BS.scaffoldBg(context);

    return Scaffold(
      backgroundColor: bgColor,
      body: _loading
          ? _buildLoader()
          : FadeTransition(
        opacity: _fadeAnim,
        child: RefreshIndicator(
          color: _BS.accent,
          backgroundColor: _BS.cardBg(context),
          onRefresh: () async {
            setState(() => _overriddenEmployeeId = null);
            await _loadData();
          },
          child: LayoutBuilder(builder: (ctx, constraints) {
            final isDesktop = constraints.maxWidth > 900;
            final hPad = isDesktop
                ? math.max(
                (constraints.maxWidth -
                    _BS.containerMaxWidth) /
                    2,
                _BS.s4)
                : _BS.s3;
            return CustomScrollView(slivers: [
              _buildNavbar(),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    hPad, _BS.s4, hPad, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_overriddenEmployeeId != null) ...[
                      _buildNfcBanner(),
                      const SizedBox(height: _BS.s3),
                    ],

                    isDesktop
                        ? _BsRow(children: [
                      _BsCol(
                          flex: 2,
                          child: _buildGreetingCard()),
                      _BsCol(
                          flex: 1,
                          child: _buildTodayMiniCard()),
                    ], gutter: _BS.gutter)
                        : Column(children: [
                      _buildGreetingCard(),
                      const SizedBox(height: _BS.s3),
                      _buildTodayMiniCard(),
                    ]),

                    const SizedBox(height: _BS.s3),
                    _buildQuickActions(),
                    const SizedBox(height: _BS.s3),

                    if (_needsVerification ||
                        _spotCheckPhotoPath != null)
                      _buildSpotCheckSection(),
                    if (_needsVerification ||
                        _spotCheckPhotoPath != null)
                      const SizedBox(height: _BS.s3),

                    _buildStatsRow(),
                    const SizedBox(height: _BS.s3),

                    isDesktop
                        ? _BsRow(children: [
                      _BsCol(
                          flex: 3,
                          child: _buildChart()),
                      _BsCol(
                          flex: 2,
                          child: _buildRecentActivity()),
                    ], gutter: _BS.gutter)
                        : Column(children: [
                      _buildChart(),
                      const SizedBox(height: _BS.s3),
                      _buildRecentActivity(),
                    ]),
                  ]),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  // ── LOADER ─────────────────────────────────────────────────────────────────
  Widget _buildLoader() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Transform.scale(
            scale: _pulseAnim.value,
            child: Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: _BS.accent.withOpacity(0.5),
                    width: 1.5),
              ),
              child: const Icon(Icons.fingerprint_rounded,
                  color: _BS.accent, size: 32),
            ),
          )),
      const SizedBox(height: 16),
      Text('Loading...',
          style: TextStyle(
              color: _BS.onSurfaceFaint(context),
              fontSize: _BS.fs5)),
    ]),
  );

  // ── NAVBAR ─────────────────────────────────────────────────────────────────
  SliverAppBar _buildNavbar() {
    final online  = ConnectivityService.instance.isOnline;
    final navBg   = _BS.scaffoldBg(context).withOpacity(0.95);
    final divColor = _BS.dividerColor(context);

    return SliverAppBar(
      pinned: true,
      expandedHeight: 0,
      backgroundColor: navBg,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF00D4FF), Color(0xFF0055BB)]),
            borderRadius: BorderRadius.circular(_BS.radiusSm),
          ),
          child: const Icon(Icons.fingerprint_rounded,
              color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('HRIS',
                style: TextStyle(
                    color: _BS.onSurface(context),
                    fontSize: 12,
                    fontWeight: _BS.fwBlack,
                    letterSpacing: 2.5)),
            const Text('BIOMETRICS',
                style: TextStyle(
                    color: _BS.accent,
                    fontSize: 7,
                    fontWeight: _BS.fwBold,
                    letterSpacing: 2.5)),
          ],
        ),
        const Spacer(),
        if (_pendingCount > 0) ...[
          _BsBadge(
            text: '$_pendingCount pending',
            bg: _BS.warning.withOpacity(0.15),
            fg: _BS.warning,
          ),
          const SizedBox(width: 8),
        ],
        _BsBadge(
          text: online ? '● ONLINE' : '○ OFFLINE',
          bg: online
              ? _BS.success.withOpacity(0.12)
              : _BS.warning.withOpacity(0.12),
          fg: online ? _BS.success : _BS.warning,
        ),
      ]),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child:
        Divider(color: divColor, height: 1, thickness: 0.5),
      ),
    );
  }

  // ── GREETING CARD ──────────────────────────────────────────────────────────
  Widget _buildGreetingCard() {
    final hour     = _now.hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
        ? 'Good Afternoon'
        : 'Good Evening';
    final clocked  = _todayAttendance?.isClockedIn ?? false;
    final textMain = _BS.onSurface(context);
    final textFaint = _BS.onSurfaceFaint(context);

    return _BsCard(
      color: _BS.greetingCard(context),
      border:
      Border.all(color: _BS.accent.withOpacity(0.2), width: 1),
      child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _BsBadge(
            text: DateFormat('EEE, MMM d').format(_now).toUpperCase(),
            bg: _BS.accent.withOpacity(0.12),
            fg: _BS.accent,
          ),
          const Spacer(),
          _BsBadge(
            text: clocked ? '● ACTIVE' : '○ OUT',
            bg: clocked
                ? _BS.success.withOpacity(0.12)
                : _BS.overlayBorder(context),
            fg: clocked ? _BS.success : textFaint,
          ),
        ]),
        const SizedBox(height: _BS.s3),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting,
                    style: TextStyle(
                        fontSize: _BS.fs5,
                        color: textFaint,
                        fontWeight: _BS.fwMedium)),
                const SizedBox(height: 4),
                Text(
                  _employee?.firstName ?? 'User',
                  style: TextStyle(
                      fontSize: _BS.fs1,
                      fontWeight: _BS.fwBlack,
                      color: textMain,
                      letterSpacing: -0.5,
                      height: 1.1),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_employee?.position ?? ''} · ${_employee?.department ?? ''}',
                  style: TextStyle(
                      fontSize: _BS.fs5,
                      color: textFaint,
                      fontWeight: _BS.fwMedium),
                ),
              ],
            ),
          ),
          const SizedBox(width: _BS.s3),
          Container(
            width: 56, height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [_BS.accent, Color(0xFF0055BB)]),
            ),
            child: Center(
              child: Text(
                _employee?.initials ?? 'EM',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: _BS.fwBlack,
                    color: Colors.white),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── TODAY MINI CARD ────────────────────────────────────────────────────────
  Widget _buildTodayMiniCard() {
    final textMain  = _BS.onSurface(context);
    final textFaint = _BS.onSurfaceFaint(context);

    return _BsCard(
      child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('TODAY',
              style: TextStyle(
                  fontSize: _BS.fs6,
                  fontWeight: _BS.fwBold,
                  color: textFaint,
                  letterSpacing: 1.5)),
          const Spacer(),
          _buildStatusBadge(),
        ]),
        const SizedBox(height: _BS.s3),
        Row(children: [
          Expanded(
              child: _buildTimeBlock(
                  'CLOCK IN',
                  _fmt12(_todayAttendance?.timeIn),
                  _BS.success,
                  Icons.login_rounded)),
          const SizedBox(width: _BS.gutterSm),
          Expanded(
              child: _buildTimeBlock(
                  'CLOCK OUT',
                  _fmt12(_todayAttendance?.timeOut),
                  _BS.purple,
                  Icons.logout_rounded)),
        ]),
        const SizedBox(height: _BS.s3),
        _BsBtn(
          label: 'View History Log',
          onTap: _openHistory,
          bg: _BS.accent,
          outline: true,
          icon: Icons.history_rounded,
        ),
      ]),
    );
  }

  Widget _buildTimeBlock(
      String label, String time, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(_BS.radiusLg),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: color,
                    fontWeight: _BS.fwBold,
                    letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 8),
          Text(time,
              style: TextStyle(
                  fontSize: 16, fontWeight: _BS.fwBlack, color: color)),
        ]),
      );

  Widget _buildStatusBadge() {
    final clocked = _todayAttendance?.isClockedIn ?? false;
    final color   = clocked ? _BS.success : _BS.warning;
    return _BsBadge(
      text: clocked ? '● ACTIVE' : '○ NOT IN',
      bg: color.withOpacity(0.1),
      fg: color,
    );
  }

  // ── QUICK ACTIONS ──────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    final actions = [
      _QA('Clock', Icons.qr_code_scanner_rounded, _BS.accent,
          [const Color(0xFF00D4FF), const Color(0xFF0066CC)],
              () => widget.onTabSwitch?.call(1)),
      _QA('Leave', Icons.beach_access_rounded, _BS.warning,
          [const Color(0xFFFFBB00), const Color(0xFFCC6600)], () {}),
      _QA('Report', Icons.bar_chart_rounded, _BS.purple,
          [const Color(0xFF9B6FFF), const Color(0xFF5533BB)],
              () => widget.onTabSwitch?.call(4)),
      _QA('Schedule', Icons.schedule_rounded, _BS.success,
          [const Color(0xFF00E5A0), const Color(0xFF006644)], () {}),
    ];

    return Row(
      children: actions.asMap().entries.map((e) {
        final a      = e.value;
        final isLast = e.key == actions.length - 1;
        return Expanded(
          child: Padding(
            padding:
            EdgeInsets.only(right: isLast ? 0 : _BS.gutterSm),
            child: _buildQACard(a),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQACard(_QA a) => GestureDetector(
    onTap: a.onTap,
    child: _BsCard(
      padding: const EdgeInsets.symmetric(vertical: _BS.s3),
      color: a.color.withOpacity(0.07),
      border: Border.all(color: a.color.withOpacity(0.2)),
      boxShadow: [],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: a.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(_BS.radius),
          ),
          child: Icon(a.icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 8),
        Text(a.label,
            style: TextStyle(
                fontSize: _BS.fs6,
                fontWeight: _BS.fwBold,
                color: a.color)),
      ]),
    ),
  );

  // ── STATS ROW ──────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final items = [
      _Stat('Present', '${_stats['present'] ?? 0}', _BS.success,
          Icons.check_circle_rounded),
      _Stat('Late', '${_stats['late'] ?? 0}', _BS.warning,
          Icons.schedule_rounded),
      _Stat('Absent', '${_stats['absent'] ?? 0}', _BS.danger,
          Icons.cancel_rounded),
      _Stat('Total Hours', '${_stats['hours'] ?? 0}h', _BS.purple,
          Icons.timer_rounded),
    ];

    return Row(
      children: items.asMap().entries.map((e) {
        final s      = e.value;
        final isLast = e.key == items.length - 1;
        return Expanded(
          child: Padding(
            padding:
            EdgeInsets.only(right: isLast ? 0 : _BS.gutterSm),
            child: _BsCard(
              color: s.color.withOpacity(0.07),
              border:
              Border.all(color: s.color.withOpacity(0.2)),
              padding: const EdgeInsets.all(_BS.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                        color: s.color.withOpacity(0.12),
                        borderRadius:
                        BorderRadius.circular(_BS.radius)),
                    child:
                    Icon(s.icon, color: s.color, size: 18),
                  ),
                  const SizedBox(height: _BS.s2),
                  Text(s.value,
                      style: TextStyle(
                          fontSize: _BS.fs2,
                          fontWeight: _BS.fwBlack,
                          color: s.color,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 2),
                  Text(s.label.toUpperCase(),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: _BS.fwBold,
                          color: s.color.withOpacity(0.6),
                          letterSpacing: 0.5)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── SPOT CHECK ─────────────────────────────────────────────────────────────
  Widget _buildSpotCheckSection() {
    final textSub = _BS.onSurface(context).withOpacity(0.7);

    if (_needsVerification) {
      return Container(
        padding: const EdgeInsets.all(_BS.s3),
        decoration: BoxDecoration(
          color: _BS.accent.withOpacity(0.06),
          borderRadius: BorderRadius.circular(_BS.radiusLg),
          border:
          Border.all(color: _BS.accent.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: _BS.accent.withOpacity(0.12),
                borderRadius:
                BorderRadius.circular(_BS.radius)),
            child: const Icon(Icons.location_on_rounded,
                color: _BS.accent, size: 20),
          ),
          const SizedBox(width: _BS.s3),
          Expanded(
            child: Text(
              'Spot check required — verify your location.',
              style: TextStyle(
                  color: textSub, fontSize: _BS.fs5),
            ),
          ),
          const SizedBox(width: _BS.s2),
          _BsBtn(
            label: _isVerifying ? 'Loading...' : 'Verify',
            onTap: _startLocationVerification,
            bg: _BS.accent,
            small: true,
          ),
        ]),
      );
    }

    if (_spotCheckPhotoPath != null) {
      return _BsCard(
        border:
        Border.all(color: _BS.success.withOpacity(0.3)),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(_BS.s3),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: _BS.success.withOpacity(0.12),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.verified_rounded,
                      color: _BS.success, size: 18),
                ),
                const SizedBox(width: 10),
                Text('Location Verified',
                    style: TextStyle(
                        color: _BS.onSurface(context),
                        fontWeight: _BS.fwBold,
                        fontSize: _BS.fs4)),
                const Spacer(),
                _BsBadge(
                  text: DateFormat('hh:mm a')
                      .format(_spotCheckTime!),
                  bg: _BS.overlayBorder(context),
                  fg: _BS.onSurfaceFaint(context),
                ),
              ]),
            ),
            if (!kIsWeb)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(_BS.radiusXl)),
                child: Image.file(
                  File(_spotCheckPhotoPath!),
                  height: 130,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ── CHART ──────────────────────────────────────────────────────────────────
  Widget _buildChart() {
    final textMain  = _BS.onSurface(context);
    final textFaint = _BS.onSurfaceFaint(context);
    final gridLine  = _BS.dividerColor(context);
    const days      = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    final bars = (_weekly.isNotEmpty
        ? _weekly
        : List.generate(
        7,
            (i) => {
          'hours': [
            7.5, 8.0, 6.5, 9.0, 8.5, 4.0, 0.0
          ][i]
        }))
        .asMap()
        .entries
        .map((e) => BarChartGroupData(
      x: e.key,
      barRods: [
        BarChartRodData(
          toY:
          (e.value['hours'] as num?)?.toDouble() ?? 0,
          gradient: LinearGradient(
            colors: [
              _BS.accent,
              _BS.accent.withOpacity(0.4)
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          width: 16,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6)),
        ),
      ],
    ))
        .toList();

    return _BsCard(
      child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('WORK HOURS',
              style: TextStyle(
                  fontSize: _BS.fs6,
                  fontWeight: _BS.fwBold,
                  color: textFaint,
                  letterSpacing: 1.5)),
          const Spacer(),
          _BsBadge(
              text: 'This Week',
              bg: _BS.accent.withOpacity(0.1),
              fg: _BS.accent,
              pill: false),
        ]),
        const SizedBox(height: 4),
        Text('Weekly Analysis',
            style: TextStyle(
                color: textMain,
                fontSize: _BS.fs3,
                fontWeight: _BS.fwBold)),
        const SizedBox(height: _BS.s3),
        SizedBox(
          height: 160,
          child: BarChart(BarChartData(
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: gridLine, strokeWidth: 0.5),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) => Text(
                    days[v.toInt() % 7],
                    style: TextStyle(
                        color: textFaint,
                        fontSize: 10,
                        fontWeight: _BS.fwSemi),
                  ),
                ),
              ),
            ),
            barGroups: bars,
          )),
        ),
      ]),
    );
  }

  // ── RECENT ACTIVITY ────────────────────────────────────────────────────────
  Widget _buildRecentActivity() {
    final textMain  = _BS.onSurface(context);
    final textFaint = _BS.onSurfaceFaint(context);

    return _BsCard(
      child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('RECENT',
              style: TextStyle(
                  fontSize: _BS.fs6,
                  fontWeight: _BS.fwBold,
                  color: textFaint,
                  letterSpacing: 1.5)),
          const Spacer(),
          GestureDetector(
            onTap: _openHistory,
            child: const Text('See all',
                style: TextStyle(
                    color: _BS.accent,
                    fontSize: _BS.fs5,
                    fontWeight: _BS.fwSemi)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Activity Log',
            style: TextStyle(
                color: textMain,
                fontSize: _BS.fs3,
                fontWeight: _BS.fwBold)),
        const SizedBox(height: _BS.s3),
        if (_recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(children: [
                Icon(Icons.inbox_rounded,
                    color: textFaint, size: 32),
                const SizedBox(height: 8),
                Text('No recent records',
                    style: TextStyle(
                        color: textFaint, fontSize: _BS.fs5)),
              ]),
            ),
          )
        else
          ..._recent.asMap().entries.map((e) => _BsListItem(
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: _BS.accent.withOpacity(0.1),
                  borderRadius:
                  BorderRadius.circular(_BS.radius)),
              child: const Icon(Icons.access_time_rounded,
                  color: _BS.accent, size: 18),
            ),
            title: e.value.date,
            subtitle:
            'In: ${e.value.timeIn ?? "--"}  ·  Out: ${e.value.timeOut ?? "Active"}',
            trailing: _BsBadge(
              text: 'Present',
              bg: _BS.success.withOpacity(0.1),
              fg: _BS.success,
              pill: false,
            ),
            isLast: e.key == _recent.length - 1,
          )),
      ]),
    );
  }

  // ── NFC BANNER ─────────────────────────────────────────────────────────────
  Widget _buildNfcBanner() => Container(
    padding: const EdgeInsets.symmetric(
        horizontal: _BS.s3, vertical: _BS.s2 + 4),
    decoration: BoxDecoration(
      color: _BS.success.withOpacity(0.08),
      borderRadius: BorderRadius.circular(_BS.radiusLg),
      border:
      Border.all(color: _BS.success.withOpacity(0.25)),
    ),
    child: Row(children: [
      const Icon(Icons.contactless_rounded,
          color: _BS.success, size: 16),
      const SizedBox(width: 10),
      const Text('NFC Keyfob View Mode',
          style: TextStyle(
              color: _BS.success,
              fontSize: _BS.fs5,
              fontWeight: _BS.fwBold)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────
class _QA {
  final String label;
  final IconData icon;
  final Color color;
  final List<Color> gradient;
  final VoidCallback onTap;
  const _QA(this.label, this.icon, this.color, this.gradient, this.onTap);
}

class _Stat {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _Stat(this.label, this.value, this.color, this.icon);
}

// ─────────────────────────────────────────────────────────────────────────────
// Verification Camera Screen
// ─────────────────────────────────────────────────────────────────────────────
class _VerificationCameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const _VerificationCameraScreen({required this.camera});

  @override
  State<_VerificationCameraScreen> createState() =>
      _VerificationCameraScreenState();
}

class _VerificationCameraScreenState
    extends State<_VerificationCameraScreen> {
  CameraController? _ctrl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _ctrl =
        CameraController(widget.camera, ResolutionPreset.medium);
    await _ctrl!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ctrl == null || !_ctrl!.value.isInitialized) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF00D4FF))));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        CameraPreview(_ctrl!),
        Center(
          child: Container(
            width: 240, height: 240,
            decoration: BoxDecoration(
              border: Border.all(
                  color: const Color(0xFF00D4FF), width: 2),
              borderRadius:
              BorderRadius.circular(_BS.radiusLg),
            ),
          ),
        ),
        Positioned(
          bottom: 50, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () async {
                final file = await _ctrl!.takePicture();
                if (context.mounted) {
                  Navigator.pop(context, file.path);
                }
              },
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00D4FF),
                  border:
                  Border.all(color: Colors.white, width: 3),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 32),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 12),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context, null),
                child: Container(
                  width: 36, height: 36,
                  decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Location Verification',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ]),
          ),
        ),
      ]),
    );
  }
}