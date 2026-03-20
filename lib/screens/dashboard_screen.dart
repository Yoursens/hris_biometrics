// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../data/local/dao/sync_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/employee.dart';
import '../models/attendance.dart';
import 'package:intl/intl.dart';
import 'attendance_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabSwitch;
  const DashboardScreen({super.key, this.onTabSwitch});
  
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Employee? _employee;
  Attendance? _todayAttendance;
  List<Attendance> _recent = [];
  Map<String, int> _stats = {};
  List<Map<String, dynamic>> _weekly = [];
  Map<String, dynamic>? _payrollSummary;
  bool _loading = true;
  bool _isDemo = false;
  int _pendingCount = 0;
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

    // Listen for NFC/Local attendance updates and switch view to that user
    _attendanceSub = DatabaseService.instance.onAttendanceChanged.listen((empId) {
      if (mounted) {
        setState(() {
          _overriddenEmployeeId = empId;
        });
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
    // If we have an overridden ID (from NFC), use it. Otherwise use logged in user.
    final loggedInId = await SecurityService.instance.getCurrentEmployeeId();
    final targetId = _overriddenEmployeeId ?? loggedInId;
    
    _isDemo = await SecurityService.instance.isDemoSession();
    
    if (targetId == null) return;

    final emp   = await DatabaseService.instance.getEmployeeById(targetId);
    final today = await DatabaseService.instance.getTodayAttendance(targetId);
    final stats = await DatabaseService.instance.getAttendanceStats(targetId);
    final week  = await DatabaseService.instance.getWeeklyWorkHours(targetId);
    final rec   = await DatabaseService.instance.getAttendanceByEmployee(targetId, limit: 5);
    final pend  = await SyncService.instance.getPendingCount();
    
    Map<String, dynamic>? payroll;
    if (today != null && today.isComplete) {
      payroll = await DatabaseService.instance.getPayrollSummary(targetId, days: 15);
    }

    if (mounted) {
      setState(() {
        _employee = emp; 
        _todayAttendance = today;
        _stats = stats; 
        _weekly = week;
        _recent = rec; 
        _pendingCount = pend;
        _payrollSummary = payroll;
        _loading = false;
      });
    }
  }

  void _openHistory() => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const AttendanceHistoryScreen()))
      .then((_) => _loadData());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.card,
        onRefresh: () async {
          setState(() => _overriddenEmployeeId = null); // Reset to logged in user on manual refresh
          await _loadData();
        },
        child: CustomScrollView(slivers: [
          _appBar(),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(delegate: SliverChildListDelegate([
              if (_overriddenEmployeeId != null) _nfcBanner(),
              _greeting(),
              const SizedBox(height: 16),
              if (_payrollSummary != null) ...[
                _buildPayrollSummaryCard(),
                const SizedBox(height: 16),
              ],
              _buildQuickActions(),
              const SizedBox(height: 16),
              _todayCard(),
              const SizedBox(height: 16),
              _statsRow(),
              const SizedBox(height: 16),
              _chart(),
              const SizedBox(height: 16),
              _recentSection(),
              const SizedBox(height: 80),
            ])),
          ),
        ]),
      ),
    );
  }

  Widget _nfcBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.contactless_rounded, color: AppColors.success, size: 18),
        const SizedBox(width: 10),
        const Expanded(child: Text('Viewing data for last tapped keyfob', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600))),
        GestureDetector(
          onTap: () {
            setState(() => _overriddenEmployeeId = null);
            _loadData();
          },
          child: const Text('RESET', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  SliverAppBar _appBar() {
    final online = ConnectivityService.instance.isOnline;
    return SliverAppBar(
      expandedHeight: 0, pinned: true,
      backgroundColor: AppColors.primary,
      automaticallyImplyLeading: false,
      title: Row(children: [
        const Text('Dashboard',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const Spacer(),
        if (_isDemo)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: const Text('DEMO MODE', 
              style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        const SizedBox(width: 8),
        Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
                color: online ? AppColors.success : AppColors.warning,
                shape: BoxShape.circle)),
        IconButton(onPressed: () {},
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _greeting() {
    final h = _now.hour;
    final g = h < 12 ? '☀️ Good Morning' : h < 17 ? '🌤 Good Afternoon' : '🌙 Good Evening';
    final displayName = _isDemo ? 'Demo Account' : (_employee?.fullName ?? 'Employee');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.accent.withValues(alpha: 0.2),
          AppColors.accentSecondary.withValues(alpha: 0.1),
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g, style: const TextStyle(fontSize: 13,
              color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(displayName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(_isDemo ? 'Guest · Trial Version' : '${_employee?.position ?? ''} · ${_employee?.department ?? ''}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ])),
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
              gradient: AppColors.gradientPrimary, shape: BoxShape.circle),
          child: Center(child: Text(_isDemo ? 'DA' : (_employee?.initials ?? 'EM'),
              style: const TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w800, color: AppColors.primary))),
        ),
      ]),
    );
  }

  Widget _buildPayrollSummaryCard() {
    final fmt = NumberFormat.currency(symbol: '₱');
    final gross = _payrollSummary!['grossPay'] as double;
    final hours = _payrollSummary!['totalHours'] as double;
    final days  = _payrollSummary!['daysPresent'] as int;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 2)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 12),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Payroll Summary', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
            Text('15-Day Cutoff Period', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
          const Spacer(),
          const Icon(Icons.auto_awesome, color: AppColors.accent, size: 16),
        ]),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fmt.format(gross), style: const TextStyle(color: AppColors.success, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1)),
            const Text('GROSS ESTIMATE', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${hours.toStringAsFixed(1)} hrs', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            Text('$days active days', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ]),
        ]),
        const SizedBox(height: 16),
        const Divider(color: AppColors.cardBorder, height: 1),
        const SizedBox(height: 12),
        const Text('Note: This summary only appears once your daily shift is complete. Calculated at ₱150/hr standard rate.', 
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontStyle: FontStyle.italic)),
      ]),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _QAItem(icon: Icons.qr_code_scanner_rounded, label: 'Clock', color: AppColors.accent, onTap: () => widget.onTabSwitch?.call(1)),
      _QAItem(icon: Icons.beach_access_rounded, label: 'Leave', color: AppColors.warning, onTap: () => _showLeaveSheet()),
      _QAItem(icon: Icons.assignment_rounded, label: 'Report', color: AppColors.accentSecondary, onTap: () => widget.onTabSwitch?.call(3)),
      _QAItem(icon: Icons.schedule_rounded, label: 'Schedule', color: AppColors.success, onTap: () => _showScheduleSheet()),
    ];

    return Row(
      children: actions.map((a) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: a.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: a.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: a.color.withValues(alpha: 0.3)),
              ),
              child: Column(children: [
                Icon(a.icon, color: a.color, size: 24),
                const SizedBox(height: 6),
                Text(a.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: a.color)),
              ]),
            ),
          ),
        ),
      )).toList(),
    );
  }

  void _showLeaveSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Request Leave', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            _buildSheetItem(
              Icons.event_available_rounded, 
              'Sick Leave', 
              'Submit a health-related leave request',
              onTap: () {
                Navigator.pop(context);
                _showLeaveForm('Sick Leave');
              },
            ),
            const SizedBox(height: 12),
            _buildSheetItem(
              Icons.beach_access_rounded, 
              'Vacation Leave', 
              'Plan your next time off',
              onTap: () {
                Navigator.pop(context);
                _showLeaveForm('Vacation Leave');
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showLeaveForm(String type) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _LeaveFormSheet(leaveType: type, employeeId: _employee?.id ?? ''),
    );
  }

  void _showScheduleSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Shift Schedule', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            _buildSheetItem(
              Icons.access_time_rounded, 
              'Standard Shift', 
              '09:00 AM - 06:00 PM',
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 12),
            _buildSheetItem(
              Icons.info_outline_rounded, 
              'Lunch Break', 
              '12:00 PM - 01:00 PM',
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetItem(IconData icon, String title, String sub, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card, 
          borderRadius: BorderRadius.circular(16), 
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(children: [
          Icon(icon, color: AppColors.accent, size: 24),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ])
        ]),
      ),
    );
  }

  Widget _todayCard() {
    final clocked = _todayAttendance?.isClockedIn ?? false;
    final done    = _todayAttendance?.isComplete  ?? false;

    String live = '--';
    if (clocked && _todayAttendance?.timeIn != null) {
      try {
        final start = DateTime.parse('${_todayAttendance!.date} ${_todayAttendance!.timeIn}');
        final d = _now.difference(start);
        live = '${d.inHours}h ${d.inMinutes % 60}m ${d.inSeconds % 60}s';
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.gradientCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text("Today's Attendance",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const Spacer(),
          _statusBadge(clocked, done),
        ]),
        const SizedBox(height: 4),
        Text(DateFormat('EEEE, MMMM d, y').format(_now),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 14),
        Row(children: [
          _TBlock(label: 'CLOCK IN', time: _fmt12(_todayAttendance?.timeIn), color: AppColors.success, icon: Icons.login_rounded),
          const SizedBox(width: 8),
          _TBlock(label: 'CLOCK OUT', time: _fmt12(_todayAttendance?.timeOut), color: AppColors.accentSecondary, icon: Icons.logout_rounded),
          const SizedBox(width: 8),
          _TBlock(label: clocked ? '⏱ LIVE' : 'HOURS', time: clocked ? live : (_todayAttendance?.formattedWorkHours ?? '--'), color: clocked ? AppColors.accent : AppColors.warning, icon: Icons.timer_rounded, isLive: clocked),
        ]),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _openHistory,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.history_rounded, color: AppColors.accent, size: 16),
              SizedBox(width: 6),
              Text('View Attendance History', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _statusBadge(bool clocked, bool done) {
    final color = clocked ? AppColors.success : done ? AppColors.info : AppColors.warning;
    final text  = clocked ? '● Active' : done ? '✓ Complete' : 'Not In';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _statsRow() => Row(children: [
    Expanded(child: _StatCard(label: 'Present', value: '${_stats['present'] ?? 0}', icon: Icons.check_circle_rounded, color: AppColors.success)),
    const SizedBox(width: 12),
    Expanded(child: _StatCard(label: 'Late', value: '${_stats['late'] ?? 0}', icon: Icons.schedule_rounded, color: AppColors.warning)),
    const SizedBox(width: 12),
    Expanded(child: _StatCard(label: 'Absent', value: '${_stats['absent'] ?? 0}', icon: Icons.cancel_rounded, color: AppColors.error)),
  ]);

  Widget _chart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: AppColors.gradientCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.cardBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Weekly Hours', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 20),
        SizedBox(height: 140,
          child: BarChart(BarChartData(
            backgroundColor: Colors.transparent,
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                const d = ['M','T','W','T','F','S','S'];
                return Text(d[v.toInt()], style: const TextStyle(color: AppColors.textMuted, fontSize: 12));
              })),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barGroups: List.generate(7, (i) {
              double hrs = 0;
              if (_weekly.length > i) hrs = _weekly[i]['hours'] as double;
              return BarChartGroupData(x: i, barRods: [BarChartRodData(toY: hrs > 0 ? hrs : 0.1, color: i == _now.weekday - 1 ? AppColors.accent : AppColors.accentSecondary.withValues(alpha: 0.5), width: 22, borderRadius: BorderRadius.circular(6))]);
            }),
          )),
        ),
      ]),
    );
  }

  Widget _recentSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Recent Activity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const Spacer(),
        GestureDetector(onTap: _openHistory, child: const Text('View All', style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: 12),
      if (_recent.isEmpty)
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)), child: const Center(child: Text('No records yet', style: TextStyle(color: AppColors.textMuted, fontSize: 13))))
      else
        Container(decoration: BoxDecoration(gradient: AppColors.gradientCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.cardBorder)), child: ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _recent.length, separatorBuilder: (_, __) => const Divider(color: AppColors.cardBorder, height: 1), itemBuilder: (_, i) => _recentRow(_recent[i]))),
    ]);
  }

  Widget _recentRow(Attendance r) {
    final sc = r.status == AttendanceStatus.late ? AppColors.warning : r.status == AttendanceStatus.absent ? AppColors.error : AppColors.success;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: sc, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.date, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          Text('Clocked: ${_fmt12(r.timeIn)} - ${_fmt12(r.timeOut)}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ])),
        Text(r.formattedWorkHours, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
      ]),
    );
  }

  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try { return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t)); } catch (_) { return t; }
  }
}

class _QAItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _QAItem({required this.icon, required this.label, required this.color, required this.onTap});
}

class _TBlock extends StatelessWidget {
  final String label;
  final String time;
  final Color color;
  final IconData icon;
  final bool isLive;
  const _TBlock({required this.label, required this.time, required this.color, required this.icon, this.isLive = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: isLive ? 0.5 : 0.2), width: isLive ? 1.5 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: color, size: 10), const SizedBox(width: 3), Text(label, style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w800))]),
          const SizedBox(height: 4),
          Text(time, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]),
    );
  }
}

class _LeaveFormSheet extends StatefulWidget {
  final String leaveType;
  final String employeeId;
  const _LeaveFormSheet({required this.leaveType, required this.employeeId});

  @override
  State<_LeaveFormSheet> createState() => _LeaveFormSheetState();
}

class _LeaveFormSheetState extends State<_LeaveFormSheet> {
  final _reasonCtrl = TextEditingController();
  DateTime _start = DateTime.now().add(const Duration(days: 1));
  DateTime _end = DateTime.now().add(const Duration(days: 1));

  Future<void> _pickRange() async {
    final res = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _start, end: _end),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.accent,
              onPrimary: AppColors.primary,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (res != null) {
      setState(() {
        _start = res.start;
        _end = res.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.edit_calendar_rounded, color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Leave Request', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 24),
          Text('TYPE: ${widget.leaveType.toUpperCase()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 16),
          
          InkWell(
            onTap: _pickRange,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
              child: Row(children: [
                Icon(Icons.calendar_today_rounded, color: AppColors.textMuted, size: 18),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Date Range', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  Text('${DateFormat('MMM dd').format(_start)} - ${DateFormat('MMM dd, yyyy').format(_end)}', 
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ])),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ]),
            ),
          ),
          
          const SizedBox(height: 16),
          TextField(
            controller: _reasonCtrl,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Reason for leave...',
              labelText: 'Reason (Optional)',
            ),
          ),
          
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () async {
                final leave = {
                  'employee_id': widget.employeeId,
                  'leave_type': widget.leaveType,
                  'start_date': DateFormat('yyyy-MM-dd').format(_start),
                  'end_date': DateFormat('yyyy-MM-dd').format(_end),
                  'reason': _reasonCtrl.text.trim(),
                };
                await DatabaseService.instance.insertLeaveRequest(leave);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${widget.leaveType} submitted successfully ✓'), backgroundColor: AppColors.success),
                  );
                }
              },
              child: const Text('Submit Request'),
            ),
          ),
        ],
      ),
    );
  }
}
