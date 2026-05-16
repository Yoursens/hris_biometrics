// lib/screens/reports_screen.dart
//
// Reports & Analytics — matches the dark navy dashboard design language.
// Same color tokens, card style, glow accents as the rest of the app.
// Uses fl_chart for the attendance trend line.
// No `on FirebaseException catch` (Flutter Web safe).
//
// CHANGE LOG:
//   • PDF export now calls PayrollPdfService.generate() which fetches the full
//     month's clock-in / clock-out records and embeds daily + total revenue.
//   • Excel / CSV exports keep the existing behaviour (snackbar confirmation).

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/payroll_pdf_service.dart';   // ← NEW
import '../models/attendance.dart';
import '../models/employee.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Design tokens — mirrors the dashboard exactly
// ══════════════════════════════════════════════════════════════════════════════
class _C {
  static const bg       = Color(0xFF0A0F2E);
  static const card     = Color(0xFF0F1535);
  static const cardAlt  = Color(0xFF131A45);
  static const accent   = Color(0xFF00D4FF);
  static const white    = Color(0xFFFFFFFF);
  static const white70  = Color(0xB3FFFFFF);
  static const white40  = Color(0x66FFFFFF);
  static const white15  = Color(0x26FFFFFF);
  static const white08  = Color(0x14FFFFFF);
  static const success  = Color(0xFF00E5A0);
  static const warning  = Color(0xFFFFBB00);
  static const error    = Color(0xFFFF4D6D);
  static const purple   = Color(0xFF9B6FFF);
  static const orange   = Color(0xFFFF6B35);
}

// ══════════════════════════════════════════════════════════════════════════════
// ReportsScreen
// ══════════════════════════════════════════════════════════════════════════════
class ReportsScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const ReportsScreen({super.key, this.initialEmployee});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabCtrl;

  int    _selectedRange = 0;
  static const _ranges  = ['This Week', 'This Month', 'This Quarter'];

  Map<String, int> _stats = {
    'present': 0, 'late': 0, 'absent': 0, 'onLeave': 0,
  };
  List<FlSpot> _trendSpots = [const FlSpot(0, 0)];
  List<Attendance> _recentHistory = [];

  bool      _loading = true;
  Employee? _employee;
  double    _totalEarned = 0.0;

  // Web-only: pulled from activity_logs
  int _webLogins  = 0;
  int _webLogouts = 0;
  int _webRegs    = 0;

  // ── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── data ───────────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      if (kIsWeb) {
        await _loadWebData();
      } else {
        await _loadMobileData();
      }
    } catch (e) {
      debugPrint('ReportsScreen._loadData: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMobileData() async {
    final empId   = await SecurityService.instance.getCurrentEmployeeId();
    Employee? emp = widget.initialEmployee;
    Map<String, int> stats = {'present': 0, 'late': 0, 'absent': 0, 'onLeave': 0};
    List<Attendance> history = [];
    double earned = 0.0;

    if (empId != null) {
      emp     = await DatabaseService.instance.getEmployeeById(empId);
      final s = await DatabaseService.instance.getAttendanceStats(empId);
      stats   = {'present': s['present'] ?? 0, 'late': s['late'] ?? 0,
        'absent': s['absent'] ?? 0, 'onLeave': 0};
      history = await DatabaseService.instance.getAttendanceByEmployee(empId, limit: 14);
      final pay = await DatabaseService.instance.getPayrollSummary(empId, days: 15);
      earned    = (pay['grossPay'] as num?)?.toDouble() ?? 0.0;
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      spots.add(FlSpot(i.toDouble(),
          history[i].status == AttendanceStatus.present ? 100.0 : 60.0));
    }

    if (mounted) {
      setState(() {
        _employee      = emp;
        _stats         = stats;
        _trendSpots    = spots.reversed.toList().isEmpty
            ? [const FlSpot(0, 0)] : spots.reversed.toList();
        _recentHistory = history;
        _totalEarned   = earned;
        _loading       = false;
      });
    }
  }

  Future<void> _loadWebData() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('activity_logs')
            .where('type', isEqualTo: 'login')
            .get(),
        FirebaseFirestore.instance
            .collection('activity_logs')
            .where('type', isEqualTo: 'logout')
            .get(),
        FirebaseFirestore.instance
            .collection('activity_logs')
            .where('type', isEqualTo: 'registration')
            .get(),
      ]);

      final logins  = results[0].docs;
      final logouts = results[1].docs;
      final regs    = results[2].docs;

      final now   = DateTime.now();
      final spots = <FlSpot>[];
      for (int d = 6; d >= 0; d--) {
        final day    = now.subtract(Duration(days: d));
        final dayStr = DateFormat('yyyy-MM-dd').format(day);
        final count  = logins.where((doc) {
          final ts = doc.data()['timestamp'];
          if (ts is! Timestamp) return false;
          return DateFormat('yyyy-MM-dd').format(ts.toDate()) == dayStr;
        }).length;
        spots.add(FlSpot((6 - d).toDouble(), count.toDouble()));
      }

      if (mounted) {
        setState(() {
          _webLogins  = logins.length;
          _webLogouts = logouts.length;
          _webRegs    = regs.length;
          _trendSpots = spots.isEmpty ? [const FlSpot(0, 0)] : spots;
          _employee   = widget.initialEmployee;
          _loading    = false;
        });
      }
    } catch (e) {
      debugPrint('_loadWebData: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          _buildRangeSelector(),
          _buildTabBar(),
          Expanded(
            child: _loading
                ? _buildLoader()
                : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildOverviewTab(),
                _buildTrendTab(),
                _buildExportTab(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final name = _employee?.fullName ?? widget.initialEmployee?.fullName ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF9B6FFF), Color(0xFF5533BB)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Reports', style: TextStyle(
            color: _C.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5,
          )),
          if (name.isNotEmpty)
            Text(name, style: const TextStyle(color: _C.white40, fontSize: 12)),
        ])),
        GestureDetector(
          onTap: _loadData,
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _C.white08, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.white15),
            ),
            child: const Icon(Icons.refresh_rounded, color: _C.accent, size: 20),
          ),
        ),
      ]),
    );
  }

  // ── range selector ─────────────────────────────────────────────────────────
  Widget _buildRangeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(children: List.generate(_ranges.length, (i) {
        final sel = _selectedRange == i;
        return GestureDetector(
          onTap: () { setState(() => _selectedRange = i); _loadData(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? _C.purple.withOpacity(0.2) : _C.white08,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? _C.purple.withOpacity(0.6) : _C.white15,
              ),
            ),
            child: Text(_ranges[i], style: TextStyle(
              color: sel ? _C.purple : _C.white40,
              fontSize: 12,
              fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
            )),
          ),
        );
      })),
    );
  }

  // ── tab bar ────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: TabBar(
        controller: _tabCtrl,
        indicatorColor: _C.accent,
        indicatorWeight: 2,
        labelColor: _C.accent,
        unselectedLabelColor: _C.white40,
        dividerColor: _C.white08,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Trend'),
          Tab(text: 'Export'),
        ],
      ),
    );
  }

  // ── loader ─────────────────────────────────────────────────────────────────
  Widget _buildLoader() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const SizedBox(width: 28, height: 28,
        child: CircularProgressIndicator(color: _C.accent, strokeWidth: 2.5)),
    const SizedBox(height: 14),
    Text('Loading reports…', style: TextStyle(color: _C.white40, fontSize: 13)),
  ]));

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 0 — Overview
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('ATTENDANCE SUMMARY'),
        const SizedBox(height: 12),
        kIsWeb ? _buildWebStatGrid() : _buildMobileStatGrid(),
        const SizedBox(height: 24),
        if (!kIsWeb && _totalEarned > 0) ...[
          _sectionLabel('ESTIMATED EARNINGS'),
          const SizedBox(height: 12),
          _buildEarningsCard(),
          const SizedBox(height: 24),
        ],
        if (!kIsWeb && _recentHistory.isNotEmpty) ...[
          _sectionLabel('RECENT RECORDS'),
          const SizedBox(height: 12),
          ..._recentHistory.take(5).map(_recentRow),
        ],
        if (kIsWeb) ...[
          _sectionLabel('DEPARTMENT PERFORMANCE'),
          const SizedBox(height: 12),
          _buildDeptCard('Corporate Operations', 0.95, _C.accent),
          const SizedBox(height: 10),
          _buildDeptCard('Field Logistics',      0.82, _C.purple),
          const SizedBox(height: 10),
          _buildDeptCard('HR & Admin',           0.88, _C.success),
          const SizedBox(height: 10),
          _buildDeptCard('IT Department',        0.91, _C.warning),
        ],
      ]),
    );
  }

  Widget _buildWebStatGrid() {
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 500 ? 3 : 2;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          _statCard('Logins',     '$_webLogins',  Icons.login_rounded,      _C.success),
          _statCard('Logouts',    '$_webLogouts', Icons.logout_rounded,      _C.purple),
          _statCard('Registered', '$_webRegs',    Icons.how_to_reg_rounded, _C.accent),
        ],
      );
    });
  }

  Widget _buildMobileStatGrid() {
    return LayoutBuilder(builder: (_, c) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.45,
        children: [
          _statCard('Present',  '${_stats['present']}', Icons.check_circle_rounded, _C.success),
          _statCard('Late',     '${_stats['late']}',    Icons.schedule_rounded,      _C.warning),
          _statCard('Absent',   '${_stats['absent']}',  Icons.cancel_rounded,        _C.error),
          _statCard('On Leave', '${_stats['onLeave']}', Icons.beach_access_rounded,  _C.accent),
        ],
      );
    });
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.white08),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(
              color: color, fontSize: 28, fontWeight: FontWeight.w900, height: 1,
            )),
            const SizedBox(height: 2),
            Text(label.toUpperCase(), style: TextStyle(
              color: _C.white40, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 0.8,
            )),
          ]),
        ],
      ),
    );
  }

  Widget _buildEarningsCard() {
    final fmt = NumberFormat.currency(symbol: '₱');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.success.withOpacity(0.15), _C.accent.withOpacity(0.08)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.success.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: _C.success.withOpacity(0.15),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.payments_rounded, color: _C.success, size: 22),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Estimated Earnings', style: TextStyle(
            color: _C.white40, fontSize: 11, fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 4),
          Text(fmt.format(_totalEarned), style: const TextStyle(
            color: _C.success, fontSize: 24, fontWeight: FontWeight.w900,
          )),
        ]),
      ]),
    );
  }

  Widget _recentRow(Attendance r) {
    final date = DateTime.tryParse(r.date);
    Color statusColor;
    IconData statusIcon;
    switch (r.status) {
      case AttendanceStatus.present:
        statusColor = _C.success; statusIcon = Icons.check_circle_rounded; break;
      case AttendanceStatus.late:
        statusColor = _C.warning; statusIcon = Icons.schedule_rounded; break;
      default:
        statusColor = _C.error;   statusIcon = Icons.cancel_rounded;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.white08),
      ),
      child: Row(children: [
        Icon(statusIcon, color: statusColor, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(
          date != null ? DateFormat('EEE, MMM d').format(date) : r.date,
          style: const TextStyle(
              color: _C.white70, fontSize: 13, fontWeight: FontWeight.w600),
        )),
        if (r.timeIn != null)
          Text(_fmt12(r.timeIn),
              style: const TextStyle(
                  color: _C.accent, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(r.status.label.toUpperCase(),
              style: TextStyle(
                  color: statusColor, fontSize: 9, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _buildDeptCard(String name, double rate, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.white08),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: const TextStyle(
            color: _C.white70, fontSize: 13, fontWeight: FontWeight.w600,
          ))),
          Text('${(rate * 100).toStringAsFixed(0)}%', style: TextStyle(
            color: color, fontSize: 14, fontWeight: FontWeight.w900,
          )),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: rate,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 7,
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 — Trend Chart
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTrendTab() {
    final hasData = _trendSpots.length > 1 ||
        (_trendSpots.length == 1 && _trendSpots.first.y > 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel(kIsWeb ? 'DAILY LOGIN TREND (LAST 7 DAYS)' : 'ATTENDANCE TREND'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          decoration: BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _C.white08),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _legendDot(_C.accent),
              const SizedBox(width: 6),
              Text(
                kIsWeb ? 'Logins per day' : 'Attendance score',
                style: const TextStyle(color: _C.white40, fontSize: 11),
              ),
              const Spacer(),
              _legendDot(_C.success),
              const SizedBox(width: 6),
              const Text('Present',
                  style: TextStyle(color: _C.white40, fontSize: 11)),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: hasData
                  ? LineChart(_buildLineData())
                  : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.show_chart_rounded, color: _C.white15, size: 48),
                const SizedBox(height: 10),
                const Text('No trend data yet',
                    style: TextStyle(color: _C.white40, fontSize: 13)),
              ])),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        if (kIsWeb) ...[
          _sectionLabel('DAY BY DAY'),
          const SizedBox(height: 12),
          ..._buildDayBreakdown(),
        ],
        if (!kIsWeb) ...[
          _sectionLabel('THIS PERIOD'),
          const SizedBox(height: 12),
          _buildPeriodSummary(),
        ],
      ]),
    );
  }

  LineChartData _buildLineData() {
    final maxY = _trendSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final adjustedMax = maxY <= 0 ? 5.0 : (maxY * 1.3).ceilToDouble();

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: adjustedMax / 4,
        getDrawingHorizontalLine: (_) =>
        const FlLine(color: _C.white08, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: kIsWeb,
            reservedSize: 28,
            interval: 1,
            getTitlesWidget: (val, _) {
              final idx = val.toInt();
              if (idx < 0 || idx > 6) return const SizedBox();
              final day = DateTime.now().subtract(Duration(days: 6 - idx));
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(DateFormat('E').format(day),
                    style: const TextStyle(
                        color: _C.white40,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (val, _) => Text(
              val.toInt().toString(),
              style: const TextStyle(color: _C.white40, fontSize: 9),
            ),
          ),
        ),
      ),
      minY: 0,
      maxY: adjustedMax,
      lineBarsData: [
        LineChartBarData(
          spots: _trendSpots,
          isCurved: true,
          curveSmoothness: 0.35,
          color: _C.accent,
          barWidth: 2.5,
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [_C.accent.withOpacity(0.22), _C.accent.withOpacity(0.0)],
            ),
          ),
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 3.5, color: _C.accent,
              strokeWidth: 2, strokeColor: _C.bg,
            ),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => _C.cardAlt,
          getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
            s.y.toStringAsFixed(0),
            const TextStyle(
                color: _C.accent, fontWeight: FontWeight.w700, fontSize: 12),
          )).toList(),
        ),
      ),
    );
  }

  List<Widget> _buildDayBreakdown() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day   = now.subtract(Duration(days: 6 - i));
      final count = i < _trendSpots.length ? _trendSpots[i].y.toInt() : 0;
      final pct   = _trendSpots.isEmpty ? 0.0
          : count / (_trendSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 0.001);
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.white08),
        ),
        child: Row(children: [
          SizedBox(
            width: 36,
            child: Text(DateFormat('EEE').format(day),
                style: const TextStyle(
                    color: _C.white40, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text(DateFormat('MMM d').format(day),
              style: const TextStyle(color: _C.white70, fontSize: 12)),
          const Spacer(),
          SizedBox(
            width: 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                backgroundColor: _C.white08,
                valueColor: const AlwaysStoppedAnimation<Color>(_C.accent),
                minHeight: 5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 24,
            child: Text('$count', style: TextStyle(
              color: count > 0 ? _C.accent : _C.white40,
              fontSize: 12, fontWeight: FontWeight.w700,
            ), textAlign: TextAlign.right),
          ),
        ]),
      );
    });
  }

  Widget _buildPeriodSummary() {
    final total   = _stats.values.fold(0, (a, b) => a + b);
    final present = _stats['present'] ?? 0;
    final rate    = total > 0 ? present / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.white08),
      ),
      child: Column(children: [
        Row(children: [
          _miniStat('${(rate * 100).toStringAsFixed(0)}%', 'Attendance Rate', _C.accent),
          _vDivider(),
          _miniStat('$present', 'Days Present', _C.success),
          _vDivider(),
          _miniStat('${_stats['late']}', 'Days Late', _C.warning),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: rate,
            backgroundColor: _C.white08,
            valueColor: AlwaysStoppedAnimation<Color>(
                rate >= 0.9 ? _C.success : rate >= 0.7 ? _C.warning : _C.error),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            rate >= 0.9 ? '🟢 Excellent'
                : rate >= 0.7 ? '🟡 Good'
                : '🔴 Needs Improvement',
            style: const TextStyle(color: _C.white40, fontSize: 11),
          ),
        ),
      ]),
    );
  }

  Widget _miniStat(String val, String label, Color color) => Expanded(
    child: Column(children: [
      Text(val, style: TextStyle(
          color: color, fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(color: _C.white40, fontSize: 10),
          textAlign: TextAlign.center),
    ]),
  );

  Widget _vDivider() => Container(width: 1, height: 40, color: _C.white15);

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 — Export
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildExportTab() {
    final formats = [
      _ExportFmt('PDF Report',  'Full month attendance + earnings breakdown',
          Icons.picture_as_pdf_rounded, _C.error),
      _ExportFmt('Excel Sheet', 'Complete data for spreadsheet analysis',
          Icons.table_chart_rounded,    _C.success),
      _ExportFmt('CSV Export',  'Raw data for system import',
          Icons.data_array_rounded,     _C.accent),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('GENERATE REPORT'),
        const SizedBox(height: 12),
        ...formats.map((f) => _exportCard(f)),
        const SizedBox(height: 24),
        _sectionLabel('RECENT EXPORTS'),
        const SizedBox(height: 12),
        _emptyExports(),
      ]),
    );
  }

  Widget _exportCard(_ExportFmt f) {
    return GestureDetector(
      onTap: () => _showExportSheet(f),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: f.color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: f.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(f.icon, color: f.color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.label, style: const TextStyle(
                  color: _C.white, fontSize: 14, fontWeight: FontWeight.w700,
                )),
                const SizedBox(height: 3),
                Text(f.sub, style: const TextStyle(
                    color: _C.white40, fontSize: 12)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: f.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: f.color.withOpacity(0.3)),
            ),
            child: Text('Generate', style: TextStyle(
              color: f.color, fontSize: 11, fontWeight: FontWeight.w700,
            )),
          ),
        ]),
      ),
    );
  }

  Widget _emptyExports() => Container(
    padding: const EdgeInsets.symmetric(vertical: 28),
    decoration: BoxDecoration(
      color: _C.card, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _C.white08),
    ),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.folder_open_rounded, color: _C.white15, size: 40),
      const SizedBox(height: 10),
      const Text('No exports yet',
          style: TextStyle(color: _C.white40, fontSize: 13)),
    ])),
  );

  void _showExportSheet(_ExportFmt f) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ExportSheet(
        fmt         : f,
        employee    : _employee ?? widget.initialEmployee,
        range       : _ranges[_selectedRange],
        totalEarned : _totalEarned,
      ),
    );
  }

  // ── shared helpers ─────────────────────────────────────────────────────────
  Widget _sectionLabel(String t) => Text(t, style: const TextStyle(
    color: _C.white40, fontSize: 10,
    fontWeight: FontWeight.w800, letterSpacing: 1.5,
  ));

  Widget _legendDot(Color c) => Container(
    width: 8, height: 8,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try {
      return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) { return t; }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Export bottom sheet
// ══════════════════════════════════════════════════════════════════════════════
class _ExportSheet extends StatefulWidget {
  final _ExportFmt fmt;
  final Employee?  employee;
  final String     range;
  final double     totalEarned;
  const _ExportSheet({
    required this.fmt, this.employee,
    required this.range, required this.totalEarned,
  });
  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool   _exporting = false;
  String _statusMsg = '';

  // ── Hourly rate lookup ─────────────────────────────────────────────────────
  // Tries to read hourlyRate from the employee's Firestore doc;
  // falls back to ₱75/hr if not set.
  Future<double> _resolveHourlyRate() async {
    final emp = widget.employee;
    if (emp == null) return 75.0;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('employeeId', isEqualTo: emp.employeeId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final rate = (data['hourlyRate'] ?? data['hourly_rate'] ?? data['rate']);
        if (rate != null) return (rate as num).toDouble();
      }
    } catch (_) {}
    return 75.0; // default ₱75/hr
  }

  Future<void> _doExport() async {
    if (_exporting) return;
    setState(() { _exporting = true; _statusMsg = 'Fetching records…'; });

    final isPdf = widget.fmt.label.contains('PDF');

    try {
      // ── PDF: full-month revenue report ────────────────────────────────────
      if (isPdf) {
        final emp = widget.employee;
        if (emp == null) throw 'No employee session. Please log in again.';

        setState(() => _statusMsg = 'Calculating earnings…');
        final hourlyRate = await _resolveHourlyRate();

        setState(() => _statusMsg = 'Building PDF…');
        await PayrollPdfService.generate(
          context,
          employee   : emp,
          hourlyRate : hourlyRate,
          month      : DateTime.now(), // current month
        );

        // Log to Firestore so admins can audit
        try {
          await FirebaseFirestore.instance.collection('pdf_exports').add({
            'employee_id'  : emp.employeeId,
            'employee_name': emp.fullName,
            'report_type'  : 'Monthly Payroll PDF',
            'hourly_rate'  : hourlyRate,
            'month'        : DateFormat('yyyy-MM').format(DateTime.now()),
            'exported_at'  : FieldValue.serverTimestamp(),
            'platform'     : kIsWeb ? 'Web' : 'Mobile',
          });
        } catch (_) {} // non-fatal

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('PDF payroll report generated ✓'),
            backgroundColor: const Color(0xFF00E5A0),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        }
        return;
      }

      // ── Excel / CSV: existing behaviour ──────────────────────────────────
      final emp = widget.employee;
      if (emp != null && !kIsWeb) {
        try {
          final pay = await DatabaseService.instance
              .getPayrollSummary(emp.id, days: 15);
          await DatabaseService.instance.savePayrollExportFile(emp, pay);
          await FirebaseFirestore.instance.collection('mobile_exports').add({
            'employee_id'  : emp.employeeId,
            'employee_name': emp.fullName,
            'report_type'  : widget.fmt.label,
            'total_earned' : widget.totalEarned,
            'range'        : widget.range,
            'exported_at'  : FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Export sync error: $e');
        }
      }

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(kIsWeb
              ? '${widget.fmt.label} preview generated'
              : '${widget.fmt.label} exported ✓'),
          backgroundColor: const Color(0xFF00E5A0),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() { _exporting = false; _statusMsg = ''; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: const Color(0xFFFF4D6D),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat.currency(symbol: '₱');
    final isPdf   = widget.fmt.label.contains('PDF');
    final thisMonth = DateFormat('MMMM yyyy').format(DateTime.now());

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Drag handle
        Center(child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: const Color(0x26FFFFFF),
            borderRadius: BorderRadius.circular(2),
          ),
        )),

        // Header
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: widget.fmt.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(widget.fmt.icon, color: widget.fmt.color, size: 20),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.fmt.label, style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.w800, fontSize: 17,
            )),
            Text(
              isPdf ? 'Monthly earnings included' : 'Ready to generate',
              style: TextStyle(color: widget.fmt.color, fontSize: 12),
            ),
          ]),
        ]),
        const SizedBox(height: 24),

        // Details
        _row('Format', widget.fmt.label),
        _row('Period', isPdf ? thisMonth : widget.range),

        // ── PDF-specific: revenue info banner ──────────────────────────────
        if (isPdf) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5A0).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF00E5A0).withOpacity(0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.monetization_on_rounded,
                  color: Color(0xFF00E5A0), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Revenue included in PDF',
                      style: TextStyle(
                          color: Color(0xFF00E5A0),
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'Every clock-in/out for $thisMonth will be '
                        'listed with daily earnings and a grand total.',
                    style: const TextStyle(
                        color: Color(0x99FFFFFF), fontSize: 10, height: 1.4),
                  ),
                ],
              )),
            ]),
          ),
        ],

        if (!kIsWeb && !isPdf && widget.totalEarned > 0) ...[
          const SizedBox(height: 4),
          _row('Earnings', fmt.format(widget.totalEarned)),
        ],

        const SizedBox(height: 28),

        // Generate button
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: _exporting ? null : _doExport,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: widget.fmt.color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _exporting
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Text(
                    _statusMsg.isNotEmpty ? _statusMsg : 'Generating…',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ])
                    : Text(
                  isPdf ? 'GENERATE PDF + REVENUE' : 'GENERATE & DOWNLOAD',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 0.5),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(children: [
      Text(label, style: const TextStyle(
          color: Color(0x66FFFFFF), fontSize: 13)),
      const Spacer(),
      Text(value, style: const TextStyle(
        color: Color(0xFFFFFFFF),
        fontWeight: FontWeight.w700, fontSize: 14,
      )),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Models
// ══════════════════════════════════════════════════════════════════════════════
class _ExportFmt {
  final String   label;
  final String   sub;
  final IconData icon;
  final Color    color;
  const _ExportFmt(this.label, this.sub, this.icon, this.color);
}