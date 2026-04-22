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

class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabSwitch;
  final Employee? initialEmployee;
  const DashboardScreen({super.key, this.onTabSwitch, this.initialEmployee});

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

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ── Design tokens ──────────────────────────────────────────────────────
  static const Color _navy      = Color(0xFF0A0F2E);
  static const Color _navyLight = Color(0xFF131A45);
  static const Color _navyCard  = Color(0xFF0F1535);
  static const Color _accent    = Color(0xFF00D4FF);
  static const Color _white     = Color(0xFFFFFFFF);
  static const Color _white70   = Color(0xB3FFFFFF);
  static const Color _white40   = Color(0x66FFFFFF);
  static const Color _white15   = Color(0x26FFFFFF);
  static const Color _white08   = Color(0x14FFFFFF);
  static const Color _success   = Color(0xFF00E5A0);
  static const Color _warning   = Color(0xFFFFBB00);
  static const Color _error     = Color(0xFFFF4D6D);
  static const Color _purple    = Color(0xFF9B6FFF);

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
        _checkAlarmConditions();
      }
    });

    _syncSub = SyncService.instance.events.listen((e) {
      if (!mounted) return;
      setState(() => _pendingCount = e.pendingCount);
      if (e.type == SyncEventType.syncDone) _loadData();
    });

    _connectSub = ConnectivityService.instance.onStatusChange.listen((on) {
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
    final loggedInId = await SecurityService.instance.getCurrentEmployeeId();
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
      today = await DatabaseService.instance.getTodayAttendance(idToQuery);
      stats = await DatabaseService.instance.getAttendanceStats(idToQuery);
      weekly = await DatabaseService.instance.getWeeklyWorkHours(idToQuery);
      recent = await DatabaseService.instance
          .getAttendanceByEmployee(idToQuery, limit: 5);
      pending = await SyncService.instance.getPendingCount();
    }

    if (mounted) {
      setState(() {
        _employee = emp;
        _todayAttendance = today;
        _stats = stats;
        _weekly = weekly;
        _recent = recent;
        _pendingCount = pending;
        _loading = false;
      });
    }
  }

  // ── Alarm Logic ────────────────────────────────────────────────────────
  Future<void> _checkAlarmConditions() async {
    if (_isShowingAlarmDialog || _loading) return;
    final now = DateTime.now();
    if (now.hour == 21 && now.minute >= 0 && now.minute < 30) {
      final isClockedIn = _todayAttendance?.isClockedIn ?? false;
      if (!isClockedIn) {
        final geoResult = await GeofenceService.instance.checkGeofence();
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
      builder: (context) => AlertDialog(
        backgroundColor: _navyCard,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: _error.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.warning_amber_rounded,
                color: _error, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('System Alert',
              style: TextStyle(
                  color: _white, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: Text(
          'You are outside the work radius and have not timed in before 9:30 PM. Please time in to stop the alarm.',
          style: TextStyle(color: _white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _error,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () {
                AlarmService.instance.stopAlarm();
                FlutterBackgroundService().invoke('stop_alarm_from_ui');
                Navigator.of(context).pop();
                setState(() => _isShowingAlarmDialog = false);
              },
              child: const Text('STOP THE ALARM',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Spot-check flow ────────────────────────────────────────────────────
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
              builder: (_) => _VerificationCameraScreen(camera: cam)));
      if (photoPath != null && mounted) {
        setState(() {
          _spotCheckPhotoPath = photoPath;
          _spotCheckTime = DateTime.now();
          _needsVerification = false;
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

  // ── BUILD ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: _loading
          ? _buildLoader()
          : FadeTransition(
        opacity: _fadeAnim,
        child: RefreshIndicator(
          color: _accent,
          backgroundColor: _navyCard,
          onRefresh: () async {
            setState(() => _overriddenEmployeeId = null);
            await _loadData();
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 900;
              final hPad = isDesktop
                  ? constraints.maxWidth * 0.08
                  : 20.0;
              return CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                        hPad, 20, hPad, 100),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (_overriddenEmployeeId != null)
                          _buildNfcBanner(),
                        _buildGreetingCard(isDesktop),
                        const SizedBox(height: 20),
                        _buildQuickActions(),
                        const SizedBox(height: 20),
                        _buildSpotCheckSection(),
                        const SizedBox(height: 20),
                        isDesktop
                            ? Row(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                flex: 3,
                                child: _buildTodayCard()),
                            const SizedBox(width: 16),
                            Expanded(
                                flex: 2,
                                child: _buildStatsColumn()),
                          ],
                        )
                            : Column(children: [
                          _buildTodayCard(),
                          const SizedBox(height: 16),
                          _buildStatsRow(),
                        ]),
                        const SizedBox(height: 20),
                        isDesktop
                            ? Row(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                flex: 3, child: _buildChart()),
                            const SizedBox(width: 16),
                            Expanded(
                                flex: 2,
                                child: _buildRecentActivity()),
                          ],
                        )
                            : Column(children: [
                          _buildChart(),
                          const SizedBox(height: 16),
                          _buildRecentActivity(),
                        ]),
                      ]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoader() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Transform.scale(
            scale: _pulseAnim.value,
            child: Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                    colors: [_accent.withOpacity(0.2), Colors.transparent]),
                border: Border.all(color: _accent.withOpacity(0.5), width: 1.5),
              ),
              child: const Icon(Icons.fingerprint_rounded,
                  color: _accent, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Loading...', style: TextStyle(color: _white40, fontSize: 13)),
      ]),
    );
  }

  // ── APP BAR ────────────────────────────────────────────────────────────
  SliverAppBar _buildAppBar() {
    final online = ConnectivityService.instance.isOnline;
    return SliverAppBar(
      expandedHeight: 0,
      pinned: true,
      backgroundColor: _navy.withOpacity(0.92),
      automaticallyImplyLeading: false,
      elevation: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          // Logo mark
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF0055BB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.fingerprint_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('HRIS',
                  style: TextStyle(
                      color: _white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
              Text('BIOMETRICS',
                  style: TextStyle(
                      color: _accent,
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5)),
            ],
          ),
          const Spacer(),
          // Pending sync badge
          if (_pendingCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _warning.withOpacity(0.35)),
              ),
              child: Row(children: [
                Icon(Icons.sync_rounded, size: 10, color: _warning),
                const SizedBox(width: 4),
                Text('$_pendingCount',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _warning)),
              ]),
            ),
          // Online/Offline indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: online
                  ? _success.withOpacity(0.1)
                  : _warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: online
                      ? _success.withOpacity(0.35)
                      : _warning.withOpacity(0.35)),
            ),
            child: Row(children: [
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Transform.scale(
                  scale: online ? _pulseAnim.value : 1.0,
                  child: Icon(Icons.circle,
                      size: 6,
                      color: online ? _success : _warning),
                ),
              ),
              const SizedBox(width: 5),
              Text(online ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: online ? _success : _warning,
                      letterSpacing: 0.5)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── GREETING CARD ──────────────────────────────────────────────────────
  Widget _buildGreetingCard(bool isDesktop) {
    final hour = _now.hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
        ? 'Good Afternoon'
        : 'Good Evening';
    final clocked = _todayAttendance?.isClockedIn ?? false;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _accent.withOpacity(0.12),
            _navyLight,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date chip
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border:
                    Border.all(color: _accent.withOpacity(0.3), width: 1),
                  ),
                  child: Text(
                    DateFormat('EEEE, MMMM d').format(_now).toUpperCase(),
                    style: TextStyle(
                        fontSize: 9,
                        color: _accent,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$greeting,',
                  style: TextStyle(
                      fontSize: 13,
                      color: _white40,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  _employee?.firstName ?? 'User',
                  style: TextStyle(
                      fontSize: isDesktop ? 32 : 26,
                      fontWeight: FontWeight.w900,
                      color: _white,
                      letterSpacing: -0.8,
                      height: 1.1),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_employee?.position ?? ''} · ${_employee?.department ?? ''}',
                  style: TextStyle(
                      fontSize: 12, color: _white40, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            children: [
              // Avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [_accent, const Color(0xFF0055BB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    _employee?.initials ?? 'EM',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Status pill
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: clocked
                      ? _success.withOpacity(0.12)
                      : _white15,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: clocked
                          ? _success.withOpacity(0.4)
                          : _white15),
                ),
                child: Text(
                  clocked ? '● ACTIVE' : '○ OUT',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: clocked ? _success : _white40,
                      letterSpacing: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── QUICK ACTIONS ──────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    final actions = [
      _QAItem(
          icon: Icons.qr_code_scanner_rounded,
          label: 'Clock',
          color: _accent,
          gradient: [const Color(0xFF00D4FF), const Color(0xFF0066CC)],
          onTap: () => widget.onTabSwitch?.call(1)),
      _QAItem(
          icon: Icons.beach_access_rounded,
          label: 'Leave',
          color: _warning,
          gradient: [const Color(0xFFFFBB00), const Color(0xFFCC6600)],
          onTap: () {}),
      _QAItem(
          icon: Icons.bar_chart_rounded,
          label: 'Report',
          color: _purple,
          gradient: [const Color(0xFF9B6FFF), const Color(0xFF5533BB)],
          onTap: () => widget.onTabSwitch?.call(4)),
      _QAItem(
          icon: Icons.schedule_rounded,
          label: 'Schedule',
          color: _success,
          gradient: [const Color(0xFF00E5A0), const Color(0xFF006644)],
          onTap: () {}),
    ];

    return Row(
      children: actions.asMap().entries.map((entry) {
        final a = entry.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
                left: entry.key == 0 ? 0 : 8,
                right: entry.key == actions.length - 1 ? 0 : 0),
            child: _QuickActionCard(item: a),
          ),
        );
      }).toList(),
    );
  }

  // ── SPOT CHECK (PRESERVED) ─────────────────────────────────────────────
  Widget _buildSpotCheckSection() {
    if (_needsVerification) return _buildVerificationBox();
    if (_spotCheckPhotoPath != null) return _buildSpotCheckPhotoCard();
    return const SizedBox.shrink();
  }

  Widget _buildVerificationBox() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withOpacity(0.25), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child:
            const Icon(Icons.location_on_rounded, color: _accent, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Spot Check',
              style: TextStyle(
                  color: _white, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 12),
        Text(
          'The system requires a quick photo verification of your work location.',
          style: TextStyle(color: _white70, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _startLocationVerification,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _isVerifying
                ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
                : const Text('Verify Now',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ]),
    );
  }

  Widget _buildSpotCheckPhotoCard() {
    return Container(
      decoration: BoxDecoration(
        color: _navyCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _success.withOpacity(0.3), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                  color: _success.withOpacity(0.12),
                  shape: BoxShape.circle),
              child: const Icon(Icons.verified_rounded,
                  color: _success, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Location Verified',
                style: TextStyle(
                    color: _white, fontWeight: FontWeight.w800, fontSize: 14)),
            const Spacer(),
            Text(
              DateFormat('hh:mm a').format(_spotCheckTime!),
              style: TextStyle(color: _white40, fontSize: 12),
            ),
          ]),
        ),
        if (!kIsWeb && _spotCheckPhotoPath != null)
          ClipRRect(
            borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(20)),
            child: Image.file(
              File(_spotCheckPhotoPath!),
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
      ]),
    );
  }

  // ── TODAY CARD ─────────────────────────────────────────────────────────
  Widget _buildTodayCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _navyCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _white15, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('TODAY',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _white40,
                  letterSpacing: 1.5)),
          const Spacer(),
          _buildStatusBadge(),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: _TimeBlock(
                label: 'CLOCK IN',
                time: _fmt12(_todayAttendance?.timeIn),
                color: _success,
                icon: Icons.login_rounded,
              )),
          const SizedBox(width: 12),
          Expanded(
              child: _TimeBlock(
                label: 'CLOCK OUT',
                time: _fmt12(_todayAttendance?.timeOut),
                color: _purple,
                icon: Icons.logout_rounded,
              )),
        ]),
        const SizedBox(height: 16),
        // History button
        GestureDetector(
          onTap: _openHistory,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accent.withOpacity(0.2), width: 1),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.history_rounded, color: _accent, size: 16),
              const SizedBox(width: 8),
              const Text('View History Log',
                  style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildStatusBadge() {
    final clocked = _todayAttendance?.isClockedIn ?? false;
    final color = clocked ? _success : _warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration:
            BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(clocked ? 'ACTIVE' : 'NOT IN',
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.5)),
      ]),
    );
  }

  // ── STATS ──────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(children: [
      Expanded(
          child: _StatChip(
              label: 'Present',
              value: '${_stats['present'] ?? 0}',
              color: _success,
              icon: Icons.check_circle_rounded)),
      const SizedBox(width: 12),
      Expanded(
          child: _StatChip(
              label: 'Late',
              value: '${_stats['late'] ?? 0}',
              color: _warning,
              icon: Icons.schedule_rounded)),
      const SizedBox(width: 12),
      Expanded(
          child: _StatChip(
              label: 'Absent',
              value: '${_stats['absent'] ?? 0}',
              color: _error,
              icon: Icons.cancel_rounded)),
    ]);
  }

  Widget _buildStatsColumn() {
    return Column(children: [
      _StatChip(
          label: 'Present',
          value: '${_stats['present'] ?? 0}',
          color: _success,
          icon: Icons.check_circle_rounded),
      const SizedBox(height: 12),
      _StatChip(
          label: 'Late',
          value: '${_stats['late'] ?? 0}',
          color: _warning,
          icon: Icons.schedule_rounded),
      const SizedBox(height: 12),
      _StatChip(
          label: 'Absent',
          value: '${_stats['absent'] ?? 0}',
          color: _error,
          icon: Icons.cancel_rounded),
    ]);
  }

  // ── CHART ──────────────────────────────────────────────────────────────
  Widget _buildChart() {
    final bars = _weekly.isNotEmpty
        ? List.generate(
      _weekly.length,
          (i) => BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: (_weekly[i]['hours'] as num?)?.toDouble() ?? 0,
            gradient: LinearGradient(
              colors: [_accent, _accent.withOpacity(0.5)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            width: 18,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6)),
          ),
        ],
      ),
    )
        : List.generate(
      7,
          (i) => BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: [7.5, 8.0, 6.5, 9.0, 8.5, 4.0, 0.0][i],
            gradient: LinearGradient(
              colors: [_accent, _accent.withOpacity(0.4)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            width: 18,
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ],
      ),
    );

    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _navyCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _white15, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('WORK HOURS',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _white40,
                  letterSpacing: 1.5)),
          const Spacer(),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('This Week',
                style: TextStyle(
                    fontSize: 10,
                    color: _accent,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Weekly Analysis',
            style: TextStyle(
                color: _white,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        SizedBox(
          height: 160,
          child: BarChart(
            BarChartData(
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: _white08,
                  strokeWidth: 0.5,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) => Text(
                      days[value.toInt() % 7],
                      style: TextStyle(
                          color: _white40,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              barGroups: bars,
            ),
          ),
        ),
      ]),
    );
  }

  // ── RECENT ACTIVITY ────────────────────────────────────────────────────
  Widget _buildRecentActivity() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _navyCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _white15, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('RECENT',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _white40,
                  letterSpacing: 1.5)),
          const Spacer(),
          GestureDetector(
            onTap: _openHistory,
            child: Text('See all',
                style: TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 4),
        const Text('Activity Log',
            style: TextStyle(
                color: _white, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        if (_recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(children: [
                Icon(Icons.inbox_rounded, color: _white40, size: 32),
                const SizedBox(height: 8),
                Text('No recent records',
                    style: TextStyle(color: _white40, fontSize: 13)),
              ]),
            ),
          )
        else
          ..._recent.asMap().entries.map((entry) {
            final r = entry.value;
            final isLast = entry.key == _recent.length - 1;
            return Column(children: [
              Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                      color: _accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.access_time_rounded,
                      color: _accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.date,
                            style: const TextStyle(
                                color: _white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const SizedBox(height: 2),
                        Text('In: ${r.timeIn ?? "--"}  ·  Out: ${r.timeOut ?? "Active"}',
                            style: TextStyle(color: _white40, fontSize: 11)),
                      ],
                    )),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Present',
                      style: TextStyle(
                          color: _success,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              if (!isLast)
                Padding(
                  padding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
                  child: Divider(
                      color: _white15, thickness: 0.5, height: 0),
                ),
            ]);
          }),
      ]),
    );
  }

  // ── NFC BANNER ─────────────────────────────────────────────────────────
  Widget _buildNfcBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _success.withOpacity(0.25), width: 1),
      ),
      child: Row(children: [
        const Icon(Icons.contactless_rounded, color: _success, size: 16),
        const SizedBox(width: 10),
        Text('NFC Keyfob View Mode',
            style: TextStyle(
                color: _success, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try {
      return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) {
      return t;
    }
  }
}

// ── QUICK ACTION CARD ──────────────────────────────────────────────────────
class _QuickActionCard extends StatefulWidget {
  final _QAItem item;
  const _QuickActionCard({required this.item});

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.item;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); a.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: a.color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: a.color.withOpacity(0.2), width: 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: a.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(a.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 8),
            Text(a.label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: a.color)),
          ]),
        ),
      ),
    );
  }
}

// ── TIME BLOCK ─────────────────────────────────────────────────────────────
class _TimeBlock extends StatelessWidget {
  final String label;
  final String time;
  final Color color;
  final IconData icon;

  const _TimeBlock(
      {required this.label,
        required this.time,
        required this.color,
        required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 8),
        Text(time,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900, color: color)),
      ]),
    );
  }
}

// ── STAT CHIP ──────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatChip(
      {required this.label,
        required this.value,
        required this.color,
        required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: -0.5)),
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color.withOpacity(0.6),
                  letterSpacing: 0.5)),
        ]),
      ]),
    );
  }
}

// ── DATA MODELS ────────────────────────────────────────────────────────────
class _QAItem {
  final IconData icon;
  final String label;
  final Color color;
  final List<Color> gradient;
  final VoidCallback onTap;

  _QAItem(
      {required this.icon,
        required this.label,
        required this.color,
        required this.gradient,
        required this.onTap});
}

// ── VERIFICATION CAMERA SCREEN (UNCHANGED) ─────────────────────────────────
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
    _ctrl = CameraController(widget.camera, ResolutionPreset.medium);
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
              child: CircularProgressIndicator(color: Color(0xFF00D4FF))));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        CameraPreview(_ctrl!),
        // Overlay frame
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00D4FF), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          bottom: 50, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () async {
                final file = await _ctrl!.takePicture();
                if (context.mounted) Navigator.pop(context, file.path);
              },
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00D4FF),
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 32),
              ),
            ),
          ),
        ),
        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context, null),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                      color: Colors.black45, shape: BoxShape.circle),
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