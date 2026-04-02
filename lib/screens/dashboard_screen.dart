// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/geofence_service.dart';
import '../data/local/dao/sync_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/employee.dart';
import '../models/attendance.dart';
import 'attendance_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabSwitch;
  const DashboardScreen({super.key, this.onTabSwitch});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Employee?  _employee;
  Attendance? _todayAttendance;
  List<Attendance>           _recent  = [];
  Map<String, int>           _stats   = {};
  List<Map<String, dynamic>> _weekly  = [];

  bool _loading            = true;
  bool _isDemo             = false;
  bool _needsVerification  = true;
  int  _pendingCount       = 0;
  bool _isVerifying        = false;

  // ── Spot-check photo ─────────────────────────────────────────────────────
  String?   _spotCheckPhotoPath;   // local file path after capture
  DateTime? _spotCheckTime;        // when it was taken

  StreamSubscription? _syncSub;
  StreamSubscription? _connectSub;
  StreamSubscription? _attendanceSub;
  late Timer _clock;
  DateTime _now = DateTime.now();
  String? _overriddenEmployeeId;

  @override
  void initState() {
    super.initState();

    _clock = Timer.periodic(const Duration(seconds: 1),
            (_) { if (mounted) setState(() => _now = DateTime.now()); });

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
    _syncSub?.cancel();
    _connectSub?.cancel();
    _attendanceSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final loggedInId = await SecurityService.instance.getCurrentEmployeeId();
    final targetId   = _overriddenEmployeeId ?? loggedInId;
    _isDemo          = await SecurityService.instance.isDemoSession();
    if (targetId == null) return;

    final emp   = await DatabaseService.instance.getEmployeeById(targetId);
    final today = await DatabaseService.instance.getTodayAttendance(targetId);
    final stats = await DatabaseService.instance.getAttendanceStats(targetId);
    final week  = await DatabaseService.instance.getWeeklyWorkHours(targetId);
    final rec   = await DatabaseService.instance
        .getAttendanceByEmployee(targetId, limit: 5);
    final pend  = await SyncService.instance.getPendingCount();

    if (mounted) {
      setState(() {
        _employee        = emp;
        _todayAttendance = today;
        _stats           = stats;
        _weekly          = week;
        _recent          = rec;
        _pendingCount    = pend;
        _loading         = false;
      });
    }
  }

  // ── Spot-check flow ──────────────────────────────────────────────────────
  Future<void> _startLocationVerification() async {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No camera found on this device.')),
          );
        }
        return;
      }

      final cam = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      if (!mounted) return;

      // Camera screen returns the saved file path (String?) on success
      final String? photoPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => _VerificationCameraScreen(camera: cam),
        ),
      );

      if (photoPath != null && mounted) {
        setState(() {
          _spotCheckPhotoPath = photoPath;
          _spotCheckTime      = DateTime.now();
          _needsVerification  = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location verified successfully ✓'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  /// Pushes the full-screen viewer for the saved photo.
  void _openPhotoViewer() {
    if (_spotCheckPhotoPath == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenPhotoViewer(
          imagePath:  _spotCheckPhotoPath!,
          capturedAt: _spotCheckTime,
        ),
      ),
    );
  }

  void _openHistory() {
    if (widget.onTabSwitch != null) {
      widget.onTabSwitch!.call(2);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AttendanceHistoryScreen()),
      ).then((_) => _loadData());
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.card,
        onRefresh: () async {
          setState(() => _overriddenEmployeeId = null);
          await _loadData();
        },
        child: CustomScrollView(slivers: [
          _appBar(),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_overriddenEmployeeId != null) _nfcBanner(),
                _greeting(),
                const SizedBox(height: 16),
                _buildQuickActions(),
                const SizedBox(height: 16),
                // Show prompt OR saved photo card
                if (_needsVerification)
                  _verificationMessageBox()
                else if (_spotCheckPhotoPath != null)
                  _spotCheckPhotoCard(),
                const SizedBox(height: 16),
                _todayCard(),
                const SizedBox(height: 16),
                _statsRow(),
                const SizedBox(height: 16),
                _chart(),
                const SizedBox(height: 16),
                _recentSection(),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Spot-check prompt ────────────────────────────────────────────────────
  Widget _verificationMessageBox() {
    final timeStr = DateFormat('hh:mm a').format(_now);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.location_on_rounded,
              color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          const Text('Spot Check Required',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          const Spacer(),
          Text(timeStr,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        const Text(
          'The system requires a quick photo verification of your current work location.',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextButton(
              onPressed: _isVerifying
                  ? null
                  : () => setState(() => _needsVerification = false),
              child: const Text('Later',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isVerifying ? null : _startLocationVerification,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                disabledBackgroundColor: AppColors.accent.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isVerifying
                  ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : const Text('Verify Now',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Saved photo card (tappable thumbnail) ────────────────────────────────
  Widget _spotCheckPhotoCard() {
    final timeStr = _spotCheckTime != null
        ? DateFormat('hh:mm a · MMM d').format(_spotCheckTime!)
        : '';

    return GestureDetector(
      onTap: _openPhotoViewer,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.success.withOpacity(0.45)),
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withOpacity(0.08),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header row ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_rounded,
                    color: AppColors.success, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Spot Check Verified',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                      if (timeStr.isNotEmpty)
                        Text(timeStr,
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 11)),
                    ]),
              ),
              // "View" pill
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.accent.withOpacity(0.3)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.open_in_full_rounded,
                      color: AppColors.accent, size: 12),
                  SizedBox(width: 5),
                  Text('View',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),

          // ── Thumbnail ──────────────────────────────────────────────────
          ClipRRect(
            borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(20)),
            child: Stack(children: [
              // Photo
              Image.file(
                File(_spotCheckPhotoPath!),
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  color: AppColors.cardBorder,
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded,
                        color: AppColors.textMuted, size: 40),
                  ),
                ),
              ),
              // Bottom gradient + hint text
              // FIX: Color.fromARGB(153, 0, 0, 0) = 60% black, const-safe
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  height: 64,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color.fromARGB(153, 0, 0, 0),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_rounded,
                          color: Colors.white70, size: 13),
                      SizedBox(width: 4),
                      Text('Tap to view full image',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── App bar ──────────────────────────────────────────────────────────────
  SliverAppBar _appBar() {
    final online = ConnectivityService.instance.isOnline;
    return SliverAppBar(
      expandedHeight: 0,
      pinned: true,
      backgroundColor: AppColors.primary,
      automaticallyImplyLeading: false,
      title: Row(children: [
        const Text('Dashboard',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const Spacer(),
        if (_isDemo)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.warning.withOpacity(0.3))),
            child: const Text('DEMO MODE',
                style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
        const SizedBox(width: 8),
        Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
                color: online ? AppColors.success : AppColors.warning,
                shape: BoxShape.circle)),
        IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.textSecondary)),
      ]),
    );
  }

  // ── Greeting ─────────────────────────────────────────────────────────────
  Widget _greeting() {
    final h = _now.hour;
    final g = h < 12
        ? '☀️ Good Morning'
        : h < 17
        ? '🌤 Good Afternoon'
        : '🌙 Good Evening';
    final displayName =
    _isDemo ? 'Demo Account' : (_employee?.fullName ?? 'Employee');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [
              AppColors.accent.withOpacity(0.2),
              AppColors.accentSecondary.withOpacity(0.1)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(displayName,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 4),
                  Text(
                      _isDemo
                          ? 'Guest · Trial Version'
                          : '${_employee?.position ?? ""} · ${_employee?.department ?? ""}',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ])),
        Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                gradient: AppColors.gradientPrimary,
                shape: BoxShape.circle),
            child: Center(
                child: Text(
                    _isDemo ? 'DA' : (_employee?.initials ?? 'EM'),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)))),
      ]),
    );
  }

  // ── Quick actions ────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    final actions = [
      _QAItem(
          icon: Icons.qr_code_scanner_rounded,
          label: 'Clock',
          color: AppColors.accent,
          onTap: () => widget.onTabSwitch?.call(1)),
      _QAItem(
          icon: Icons.beach_access_rounded,
          label: 'Leave',
          color: AppColors.warning,
          onTap: () => _showLeaveSheet()),
      _QAItem(
          icon: Icons.assignment_rounded,
          label: 'Report',
          color: AppColors.accentSecondary,
          onTap: () => widget.onTabSwitch?.call(4)),
      _QAItem(
          icon: Icons.schedule_rounded,
          label: 'Schedule',
          color: AppColors.success,
          onTap: () => _showScheduleSheet()),
    ];
    return Row(
        children: actions
            .map((a) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                  onTap: a.onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                          color: a.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: a.color.withOpacity(0.3))),
                      child: Column(children: [
                        Icon(a.icon, color: a.color, size: 24),
                        const SizedBox(height: 6),
                        Text(a.label,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: a.color)),
                      ]))),
            )))
            .toList());
  }

  void _showLeaveSheet() {
    showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Request Leave',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 20),
                  _buildSheetItem(Icons.event_available_rounded,
                      'Sick Leave', 'Submit health-related request',
                      onTap: () {
                        Navigator.pop(context);
                        _showLeaveForm('Sick Leave');
                      }),
                  const SizedBox(height: 12),
                  _buildSheetItem(Icons.beach_access_rounded,
                      'Vacation Leave', 'Plan your next time off',
                      onTap: () {
                        Navigator.pop(context);
                        _showLeaveForm('Vacation Leave');
                      }),
                  const SizedBox(height: 24),
                ])));
  }

  void _showLeaveForm(String type) {
    showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => _LeaveFormSheet(
            leaveType: type, employeeId: _employee?.id ?? ''));
  }

  void _showScheduleSheet() {
    showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Shift Schedule',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 20),
                  _buildSheetItem(Icons.access_time_rounded,
                      'Standard Shift', '09:00 AM - 06:00 PM',
                      onTap: () => Navigator.pop(context)),
                  const SizedBox(height: 12),
                  _buildSheetItem(Icons.info_outline_rounded,
                      'Lunch Break', '12:00 PM - 01:00 PM',
                      onTap: () => Navigator.pop(context)),
                  const SizedBox(height: 24),
                ])));
  }

  Widget _buildSheetItem(IconData icon, String title, String sub,
      {VoidCallback? onTap}) {
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder)),
            child: Row(children: [
              Icon(icon, color: AppColors.accent, size: 24),
              const SizedBox(width: 16),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text(sub,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ]),
            ])));
  }

  // ── Today card ───────────────────────────────────────────────────────────
  Widget _todayCard() {
    final clocked = _todayAttendance?.isClockedIn ?? false;
    final done    = _todayAttendance?.isComplete  ?? false;
    String live = '--';
    if (clocked && _todayAttendance?.timeIn != null) {
      try {
        final start = DateTime.parse(
            '${_todayAttendance!.date} ${_todayAttendance!.timeIn}');
        final d = _now.difference(start);
        live = '${d.inHours}h ${d.inMinutes % 60}m ${d.inSeconds % 60}s';
      } catch (_) {}
    }
    return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            gradient: AppColors.gradientCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text("Today's Attendance",
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const Spacer(),
                _statusBadge(clocked, done),
              ]),
              const SizedBox(height: 4),
              Text(DateFormat('EEEE, MMMM d, y').format(_now),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 14),
              Row(children: [
                _TBlock(
                    label: 'CLOCK IN',
                    time: _fmt12(_todayAttendance?.timeIn),
                    color: AppColors.success,
                    icon: Icons.login_rounded),
                const SizedBox(width: 8),
                _TBlock(
                    label: 'CLOCK OUT',
                    time: _fmt12(_todayAttendance?.timeOut),
                    color: AppColors.accentSecondary,
                    icon: Icons.logout_rounded),
                const SizedBox(width: 8),
                _TBlock(
                    label: clocked ? '⏱ LIVE' : 'HOURS',
                    time: clocked
                        ? live
                        : (_todayAttendance?.formattedWorkHours ?? '--'),
                    color:
                    clocked ? AppColors.accent : AppColors.warning,
                    icon: Icons.timer_rounded,
                    isLive: clocked),
              ]),
              const SizedBox(height: 14),
              InkWell(
                  onTap: _openHistory,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.accent.withOpacity(0.2))),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_rounded,
                                color: AppColors.accent, size: 16),
                            SizedBox(width: 6),
                            Text('View Attendance History',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent)),
                          ]))),
            ]));
  }

  Widget _statusBadge(bool clocked, bool done) {
    final color = clocked
        ? AppColors.success
        : done
        ? AppColors.info
        : AppColors.warning;
    final text =
    clocked ? '● Active' : done ? '✓ Complete' : 'Not In';
    return Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)));
  }

  Widget _statsRow() => Row(children: [
    Expanded(
        child: _StatCard(
            label: 'Present',
            value: '${_stats['present'] ?? 0}',
            icon: Icons.check_circle_rounded,
            color: AppColors.success)),
    const SizedBox(width: 12),
    Expanded(
        child: _StatCard(
            label: 'Late',
            value: '${_stats['late'] ?? 0}',
            icon: Icons.schedule_rounded,
            color: AppColors.warning)),
    const SizedBox(width: 12),
    Expanded(
        child: _StatCard(
            label: 'Absent',
            value: '${_stats['absent'] ?? 0}',
            icon: Icons.cancel_rounded,
            color: AppColors.error)),
  ]);

  Widget _chart() {
    return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            gradient: AppColors.gradientCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder)),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Weekly Hours',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          SizedBox(
              height: 140,
              child: BarChart(BarChartData(
                  backgroundColor: Colors.transparent,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                const d = [
                                  'M', 'T', 'W', 'T', 'F', 'S', 'S'
                                ];
                                return Text(d[v.toInt()],
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12));
                              })),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false))),
                  barGroups: List.generate(7, (i) {
                    double hrs = 0;
                    if (_weekly.length > i)
                      hrs = _weekly[i]['hours'] as double;
                    return BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                          toY: hrs > 0 ? hrs : 0.1,
                          color: i == _now.weekday - 1
                              ? AppColors.accent
                              : AppColors.accentSecondary
                              .withOpacity(0.5),
                          width: 22,
                          borderRadius: BorderRadius.circular(6))
                    ]);
                  })))),
        ]));
  }

  Widget _recentSection() {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Recent Activity',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const Spacer(),
            InkWell(
                onTap: _openHistory,
                child: const Text('View All',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 12),
          if (_recent.isEmpty)
            Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder)),
                child: const Center(
                    child: Text('No records yet',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 13))))
          else
            Container(
                decoration: BoxDecoration(
                    gradient: AppColors.gradientCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.cardBorder)),
                child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _recent.length,
                    separatorBuilder: (_, __) => const Divider(
                        color: AppColors.cardBorder, height: 1),
                    itemBuilder: (_, i) => _recentRow(_recent[i]))),
        ]);
  }

  Widget _recentRow(Attendance r) {
    final sc = r.status == AttendanceStatus.late
        ? AppColors.warning
        : r.status == AttendanceStatus.absent
        ? AppColors.error
        : AppColors.success;
    return Padding(
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration:
              BoxDecoration(color: sc, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.date,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    Text(
                        'Clocked: ${_fmt12(r.timeIn)} - ${_fmt12(r.timeOut)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ])),
          Text(r.formattedWorkHours,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent)),
        ]));
  }

  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try {
      return DateFormat('hh:mm a')
          .format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) { return t; }
  }

  Widget _nfcBanner() {
    return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.success.withOpacity(0.3))),
        child: Row(children: [
          const Icon(Icons.contactless_rounded,
              color: AppColors.success, size: 18),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Viewing data for last tapped keyfob',
                  style: TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          GestureDetector(
              onTap: () {
                setState(() => _overriddenEmployeeId = null);
                _loadData();
              },
              child: const Text('RESET',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800))),
        ]));
  }
}

// ─── Verification Camera Screen ───────────────────────────────────────────────
/// Self-contained. Returns the saved file path (String) via Navigator.pop,
/// or null if cancelled / failed.
class _VerificationCameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const _VerificationCameraScreen({required this.camera});

  @override
  State<_VerificationCameraScreen> createState() =>
      _VerificationCameraScreenState();
}

class _VerificationCameraScreenState
    extends State<_VerificationCameraScreen> {
  CameraController? _controller;
  bool _ready      = false;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  // ── FIX: Use ResolutionPreset.medium to prevent freeze on mid-range devices.
  //         Guard with !mounted BEFORE calling setState.
  Future<void> _initController() async {
    final ctrl = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _ready = true;
      });
    } catch (e) {
      await ctrl.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera init failed: $e')),
        );
        Navigator.pop(context, null);
      }
    }
  }

  Future<void> _capture() async {
    if (_processing || _controller == null || !_ready) return;
    setState(() => _processing = true);
    try {
      final XFile file = await _controller!.takePicture();
      // Return the file path to the dashboard
      if (mounted) Navigator.pop(context, file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Capture failed: $e'),
              backgroundColor: AppColors.error),
        );
        setState(() => _processing = false);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: !_ready || _controller == null
          ? const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: AppColors.accent),
          SizedBox(height: 16),
          Text('Opening camera…',
              style: TextStyle(color: Colors.white70)),
        ]),
      )
          : Stack(fit: StackFit.expand, children: [
        // Preview
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize!.height,
                height: _controller!.value.previewSize!.width,
                child: CameraPreview(_controller!),
              ),
            ),
          ),
        ),
        // Accent border overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: AppColors.accent.withOpacity(0.4),
                  width: 2),
            ),
          ),
        ),
        // Header text
        const Positioned(
          top: 60, left: 20, right: 20,
          child: Column(children: [
            Text('SPOT CHECK',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: 2)),
            SizedBox(height: 8),
            Text('Capture your current workplace',
                style: TextStyle(
                    color: Colors.white70, fontSize: 13)),
          ]),
        ),
        // Shutter button
        Positioned(
          bottom: 60, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _processing ? null : _capture,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.accent, width: 4),
                ),
                child: _processing
                    ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                        color: AppColors.accent))
                    : const Icon(Icons.camera_alt_rounded,
                    color: AppColors.accent, size: 36),
              ),
            ),
          ),
        ),
        // Close
        Positioned(
          top: 50, right: 20,
          child: IconButton(
            icon: const Icon(Icons.close,
                color: Colors.white, size: 30),
            onPressed: () => Navigator.pop(context, null),
          ),
        ),
      ]),
    );
  }
}

// ─── Full-Screen Photo Viewer ─────────────────────────────────────────────────
class _FullScreenPhotoViewer extends StatefulWidget {
  final String    imagePath;
  final DateTime? capturedAt;
  const _FullScreenPhotoViewer(
      {required this.imagePath, this.capturedAt});

  @override
  State<_FullScreenPhotoViewer> createState() =>
      _FullScreenPhotoViewerState();
}

class _FullScreenPhotoViewerState
    extends State<_FullScreenPhotoViewer> {
  bool _showOverlay = true;
  final TransformationController _transform =
  TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = widget.capturedAt != null
        ? DateFormat('MMMM d, yyyy · hh:mm a')
        .format(widget.capturedAt!)
        : '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Toggle overlay on tap
        onTap: () =>
            setState(() => _showOverlay = !_showOverlay),
        child: Stack(fit: StackFit.expand, children: [
          // ── Pinch-to-zoom image ─────────────────────────────────────
          InteractiveViewer(
            transformationController: _transform,
            minScale: 0.8,
            maxScale: 5.0,
            child: Center(
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_rounded,
                      color: Colors.white38, size: 72),
                ),
              ),
            ),
          ),

          // ── Top bar ─────────────────────────────────────────────────
          AnimatedOpacity(
            opacity: _showOverlay ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            child: IgnorePointer(
              ignoring: !_showOverlay,
              child: Column(children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Row(children: [
                        IconButton(
                          icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                            child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  const Text('Spot Check Photo',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16)),
                                  if (timeStr.isNotEmpty)
                                    Text(timeStr,
                                        style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12)),
                                ])),
                        // Reset zoom button
                        IconButton(
                          icon: const Icon(
                              Icons.zoom_out_map_rounded,
                              color: Colors.white70),
                          tooltip: 'Reset zoom',
                          onPressed: () =>
                          _transform.value =
                              Matrix4.identity(),
                        ),
                      ]),
                    ),
                  ),
                ),
                const Spacer(),
              ]),
            ),
          ),

          // ── Bottom bar ───────────────────────────────────────────────
          AnimatedOpacity(
            opacity: _showOverlay ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            child: IgnorePointer(
              ignoring: !_showOverlay,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 48),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Verified badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.success
                                    .withOpacity(0.4)),
                          ),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded,
                                    color: AppColors.success,
                                    size: 14),
                                SizedBox(width: 6),
                                Text('Workplace verified',
                                    style: TextStyle(
                                        color: AppColors.success,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ]),
                        ),
                        const SizedBox(width: 14),
                        // Zoom hint
                        const Text('Pinch to zoom',
                            style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12)),
                      ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Shared helper classes ────────────────────────────────────────────────────
class _QAItem {
  final IconData    icon;
  final String      label;
  final Color       color;
  final VoidCallback onTap;
  _QAItem({required this.icon, required this.label,
    required this.color, required this.onTap});
}

class _TBlock extends StatelessWidget {
  final String   label;
  final String   time;
  final Color    color;
  final IconData icon;
  final bool     isLive;
  const _TBlock({required this.label, required this.time,
    required this.color, required this.icon,
    this.isLive = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
        child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: color.withOpacity(isLive ? 0.5 : 0.2),
                    width: isLive ? 1.5 : 1)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(icon, color: color, size: 10),
                    const SizedBox(width: 3),
                    Text(label,
                        style: TextStyle(
                            fontSize: 8,
                            color: color,
                            fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 4),
                  Text(time,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ])));
  }
}

class _StatCard extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;
  final Color    color;
  const _StatCard({required this.label, required this.value,
    required this.icon,  required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: color)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMuted)),
            ]));
  }
}

class _LeaveFormSheet extends StatefulWidget {
  final String leaveType;
  final String employeeId;
  const _LeaveFormSheet(
      {required this.leaveType, required this.employeeId});

  @override
  State<_LeaveFormSheet> createState() => _LeaveFormSheetState();
}

class _LeaveFormSheetState extends State<_LeaveFormSheet> {
  final _reasonCtrl = TextEditingController();
  DateTime _start = DateTime.now().add(const Duration(days: 1));
  DateTime _end   = DateTime.now().add(const Duration(days: 1));

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24,
            MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Leave Request',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 24),
              Text('TYPE: ${widget.leaveType.toUpperCase()}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted)),
              const SizedBox(height: 16),
              TextField(
                  controller: _reasonCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Reason (Optional)')),
              const SizedBox(height: 24),
              SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                      onPressed: () async {
                        final leave = {
                          'employee_id': widget.employeeId,
                          'leave_type':  widget.leaveType,
                          'start_date':
                          DateFormat('yyyy-MM-dd').format(_start),
                          'end_date':
                          DateFormat('yyyy-MM-dd').format(_end),
                          'reason': _reasonCtrl.text.trim(),
                        };
                        await DatabaseService.instance
                            .insertLeaveRequest(leave);
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text('Submit Request'))),
            ]));
  }
}