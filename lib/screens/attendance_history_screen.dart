// lib/screens/attendance_history_screen.dart
//
// FIX: Web now reads from `activity_logs` (type=login / type=logout)
//      which is exactly what admin_dashboard.dart and login_screen.dart write to.
//      No `on FirebaseException catch` anywhere (Flutter Web safe).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../data/local/dao/sync_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/attendance.dart';
import '../models/employee.dart';

// ── Design tokens ──────────────────────────────────────────────────────────
class _C {
  static const Color navy    = Color(0xFF0A0F2E);
  static const Color card    = Color(0xFF0F1535);
  static const Color cardAlt = Color(0xFF131A45);
  static const Color accent  = Color(0xFF00D4FF);
  static const Color success = Color(0xFF00E5A0);
  static const Color warning = Color(0xFFFFBB00);
  static const Color error   = Color(0xFFFF4D6D);
  static const Color purple  = Color(0xFF9B6FFF);
  static const Color white   = Color(0xFFFFFFFF);
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white40 = Color(0x66FFFFFF);
  static const Color white15 = Color(0x26FFFFFF);
  static const Color white08 = Color(0x14FFFFFF);
}

class AttendanceHistoryScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const AttendanceHistoryScreen({super.key, this.initialEmployee});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen>
    with SingleTickerProviderStateMixin {

  Employee? _employee;

  // Mobile records
  List<Attendance> _localRecords = [];

  // Web records — built from activity_logs
  List<Map<String, dynamic>> _loginLogs  = [];
  List<Map<String, dynamic>> _logoutLogs = [];
  List<Map<String, dynamic>> _combined   = []; // paired login+logout per day

  bool    _loading  = true;
  bool    _syncing  = false;
  int     _pendingCount = 0;
  String? _error;

  StreamSubscription? _syncSub;
  StreamSubscription? _connectSub;
  StreamSubscription? _attendanceSub;

  late TabController _tabController;

  // ── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kIsWeb ? 3 : 1, vsync: this);

    if (!kIsWeb) {
      _syncSub = SyncService.instance.events.listen((e) async {
        if (!mounted) return;
        setState(() => _pendingCount = e.pendingCount);
        if (e.type == SyncEventType.syncDone) {
          await _loadData();
          if (e.syncedCount > 0) {
            _snack('✓ ${e.syncedCount} record(s) synced', _C.success);
          }
        }
      });
      _connectSub = ConnectivityService.instance.onStatusChange.listen((online) {
        if (mounted && online) _sync();
      });
      _attendanceSub =
          DatabaseService.instance.onAttendanceChanged.listen((_) {
            if (mounted) _loadData();
          });
    }

    _loadData();
    if (!kIsWeb) _sync();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _syncSub?.cancel();
    _connectSub?.cancel();
    _attendanceSub?.cancel();
    super.dispose();
  }

  // ── data loading ───────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      if (kIsWeb) {
        await _loadWebData();
      } else {
        await _loadMobileData();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── WEB: reads from `activity_logs` ───────────────────────────────────────
  //
  // Fields written by login_screen.dart / admin_dashboard.dart:
  //   type            : 'login' | 'logout' | 'registration'
  //   employee_id     : String
  //   employee_name   : String
  //   timestamp       : Timestamp  (server timestamp)
  //   device          : String
  //
  Future<void> _loadWebData() async {
    final emp   = widget.initialEmployee;
    final empId = emp?.employeeId ?? emp?.id ?? '';

    try {
      // ── fetch logins ──────────────────────────────────────────────────────
      // NOTE: No .orderBy() — avoids composite index requirement.
      // Sorting is done in Dart after fetch.
      Query loginQuery = FirebaseFirestore.instance
          .collection('activity_logs')
          .where('type', isEqualTo: 'login');

      if (empId.isNotEmpty) {
        loginQuery = loginQuery.where('employee_id', isEqualTo: empId);
      }

      // ── fetch logouts ─────────────────────────────────────────────────────
      Query logoutQuery = FirebaseFirestore.instance
          .collection('activity_logs')
          .where('type', isEqualTo: 'logout');

      if (empId.isNotEmpty) {
        logoutQuery = logoutQuery.where('employee_id', isEqualTo: empId);
      }

      final results = await Future.wait([
        loginQuery.get(),
        logoutQuery.get(),
      ]);

      // Sort by timestamp descending in Dart — no composite index needed
      int tsSort(Map<String, dynamic> a, Map<String, dynamic> b) {
        final ta = a['timestamp'];
        final tb = b['timestamp'];
        if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
        return 0;
      }

      final logins = results[0]
          .docs
          .map((d) => {'_docId': d.id, ...d.data() as Map<String, dynamic>})
          .toList()
        ..sort(tsSort);

      final logouts = results[1]
          .docs
          .map((d) => {'_docId': d.id, ...d.data() as Map<String, dynamic>})
          .toList()
        ..sort(tsSort);

      // ── pair logins with logouts by employee + date ───────────────────────
      //
      // Strategy: for each login, find the earliest logout from the same
      // employee on the same calendar date that hasn't been paired yet.
      //
      final combined = <Map<String, dynamic>>[];
      final usedLogoutIds = <String>{};

      for (final login in logins) {
        final ts = login['timestamp'];
        DateTime? loginDt;
        if (ts is Timestamp) loginDt = ts.toDate();
        final loginDateStr = loginDt != null
            ? DateFormat('yyyy-MM-dd').format(loginDt) : '';
        final eid = (login['employee_id'] ?? '').toString();

        // Find a matching logout (same employee, same date, not yet used)
        Map<String, dynamic>? matchedLogout;
        for (final logout in logouts) {
          if (usedLogoutIds.contains(logout['_docId'])) continue;
          final lts = logout['timestamp'];
          DateTime? logoutDt;
          if (lts is Timestamp) logoutDt = lts.toDate();
          final logoutDateStr = logoutDt != null
              ? DateFormat('yyyy-MM-dd').format(logoutDt) : '';
          final leid = (logout['employee_id'] ?? '').toString();

          if (leid == eid && logoutDateStr == loginDateStr) {
            matchedLogout = logout;
            usedLogoutIds.add(logout['_docId'].toString());
            break;
          }
        }

        combined.add({
          'date'          : loginDateStr,
          'employee_id'   : eid,
          'employee_name' : (login['employee_name'] ?? '').toString(),
          'device'        : (login['device'] ?? '').toString(),
          'login_ts'      : login['timestamp'],
          'logout_ts'     : matchedLogout?['timestamp'],
          'has_out'       : matchedLogout != null,
        });
      }

      // Already ordered descending by Firestore query
      if (mounted) {
        setState(() {
          _employee   = emp;
          _loginLogs  = logins;
          _logoutLogs = logouts;
          _combined   = combined;
          _loading    = false;
        });
      }
    } catch (e) {
      // Plain catch — no typed FirebaseException (Flutter Web safe)
      debugPrint('_loadWebData error: $e');
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Mobile: reads from local SQLite ───────────────────────────────────────
  Future<void> _loadMobileData() async {
    final empId = await SecurityService.instance.getCurrentEmployeeId();
    Employee? emp = widget.initialEmployee;
    List<Attendance> records = [];
    int pending = 0;

    if (empId != null) {
      emp     = await DatabaseService.instance.getEmployeeById(empId);
      records = await DatabaseService.instance
          .getAttendanceByEmployee(empId, limit: 90);
      pending = await SyncService.instance.getPendingCount();
    }

    if (mounted) {
      setState(() {
        _employee     = emp;
        _localRecords = records;
        _pendingCount = pending;
        _loading      = false;
      });
    }
  }

  Future<void> _sync() async {
    if (kIsWeb || _syncing) return;
    if (mounted) setState(() => _syncing = true);
    await DatabaseService.instance.syncLocalFilesToDatabase();
    await SyncService.instance.syncPending();
    if (mounted) setState(() => _syncing = false);
    await _loadData();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── time helpers ───────────────────────────────────────────────────────────
  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try {
      return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) { return t; }
  }

  String _fmtTimestamp(dynamic ts) {
    if (ts == null) return '--:--';
    if (ts is Timestamp) {
      return DateFormat('hh:mm a').format(ts.toDate().toLocal());
    }
    return '--:--';
  }

  String _fmtDate(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      return DateFormat('EEE, MMM d yyyy').format(ts.toDate().toLocal());
    }
    return '—';
  }

  String _durationFromTs(dynamic loginTs, dynamic logoutTs) {
    if (loginTs == null || loginTs is! Timestamp) return '--';
    final start = loginTs.toDate();
    final end   = logoutTs is Timestamp ? logoutTs.toDate() : DateTime.now();
    final diff  = end.difference(start);
    if (diff.isNegative) return '--';
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  String _durationStr(String? timeIn, String? timeOut, String? date) {
    if (timeIn == null || date == null) return '--';
    try {
      final start = DateTime.parse('${date}T$timeIn');
      final end   = timeOut != null
          ? DateTime.parse('${date}T$timeOut') : DateTime.now();
      final diff  = end.difference(start);
      if (diff.isNegative) return '--';
      return '${diff.inHours}h ${diff.inMinutes % 60}m';
    } catch (_) { return '--'; }
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.navy,
      body: Column(children: [
        _buildHeader(),
        if (kIsWeb) _buildTabBar(),
        Expanded(
          child: _loading
              ? _buildLoader()
              : _error != null
              ? _buildError()
              : kIsWeb
              ? _buildWebContent()
              : _buildMobileContent(),
        ),
      ]),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, kIsWeb ? 20 : MediaQuery.of(context).padding.top + 16, 20, 16),
      decoration: BoxDecoration(
        color: _C.card,
        border: Border(bottom: BorderSide(color: _C.white15, width: 0.5)),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF00D4FF), Color(0xFF0055BB)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.history_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Attendance History',
                style: TextStyle(
                    color: _C.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(
              _employee?.fullName ??
                  widget.initialEmployee?.fullName ??
                  'All Records',
              style: const TextStyle(color: _C.white40, fontSize: 12),
            ),
          ]),
        ),

        // Web: refresh button
        if (kIsWeb)
          GestureDetector(
            onTap: _loadData,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _C.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _C.accent.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.refresh_rounded, color: _C.accent, size: 14),
                const SizedBox(width: 6),
                Text('Refresh',
                    style: TextStyle(
                        color: _C.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),

        // Mobile: pending badge + sync
        if (!kIsWeb) ...[
          if (_pendingCount > 0) ...[
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _C.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.warning.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_upload_outlined, color: _C.warning, size: 11),
                const SizedBox(width: 3),
                Text('$_pendingCount',
                    style: TextStyle(
                        fontSize: 10,
                        color: _C.warning,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: _syncing ? null : _sync,
            child: _syncing
                ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: _C.accent, strokeWidth: 2))
                : const Icon(Icons.sync_rounded, color: _C.accent, size: 22),
          ),
        ],
      ]),
    );
  }

  // ── TAB BAR ────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      color: _C.card,
      child: TabBar(
        controller: _tabController,
        indicatorColor: _C.accent,
        indicatorWeight: 2,
        labelColor: _C.accent,
        unselectedLabelColor: _C.white40,
        labelStyle:
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        tabs: const [
          Tab(text: 'All Records'),
          Tab(text: 'Logins'),
          Tab(text: 'Logouts'),
        ],
      ),
    );
  }

  // ── LOADER ────────────────────────────────────────────────────────────────
  Widget _buildLoader() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(
          width: 32, height: 32,
          child: CircularProgressIndicator(
              color: _C.accent, strokeWidth: 2.5)),
      const SizedBox(height: 16),
      Text('Loading records…',
          style: TextStyle(color: _C.white40, fontSize: 13)),
    ]),
  );

  // ── ERROR ─────────────────────────────────────────────────────────────────
  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _C.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.error.withOpacity(0.3)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: _C.error, size: 40),
          const SizedBox(height: 12),
          Text('Failed to load records',
              style: TextStyle(
                  color: _C.error,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_error ?? '',
              style: TextStyle(color: _C.white40, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _loadData,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  color: _C.accent,
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('Retry',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    ),
  );

  // ── STATS ROW ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final total   = kIsWeb ? _combined.length  : _localRecords.length;
    final withOut = kIsWeb
        ? _combined.where((r) => r['has_out'] == true).length
        : _localRecords.where((r) => r.timeOut != null).length;
    final active  = total - withOut;

    return Container(
      margin: const EdgeInsets.all(16),
      child: Row(children: [
        _StatChip(label: 'Total',     value: '$total',   color: _C.accent,   icon: Icons.list_alt_rounded),
        const SizedBox(width: 10),
        _StatChip(label: 'Completed', value: '$withOut', color: _C.success,  icon: Icons.check_circle_rounded),
        const SizedBox(width: 10),
        _StatChip(label: 'Active',    value: '$active',  color: _C.warning,  icon: Icons.timelapse_rounded),
      ]),
    );
  }

  // ── WEB CONTENT ───────────────────────────────────────────────────────────
  Widget _buildWebContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildCombinedList(),
        _buildLoginList(),
        _buildLogoutList(),
      ],
    );
  }

  // ─ Tab 0: All Records (paired login + logout) ──────────────────────────
  Widget _buildCombinedList() {
    if (_combined.isEmpty) {
      return _buildEmptyState(
        'No attendance records found',
        subtitle: 'Login and logout activity will appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        _buildStatsRow(),
        ..._combined.map((r) => _CombinedCard(
          record    : r,
          fmtTs     : _fmtTimestamp,
          fmtDate   : _fmtDate,
          durationTs: _durationFromTs,
        )),
        const SizedBox(height: 20),
      ],
    );
  }

  // ─ Tab 1: Login logs ───────────────────────────────────────────────────
  Widget _buildLoginList() {
    if (_loginLogs.isEmpty) {
      return _buildEmptyState('No login records found');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _countBadge(
              '${_loginLogs.length} Login Records',
              Icons.login_rounded,
              _C.success),
        ),
        ..._loginLogs.map((r) => _ActivityLogCard(
          record  : r,
          type    : 'login',
          fmtTs   : _fmtTimestamp,
          fmtDate : _fmtDate,
        )),
        const SizedBox(height: 20),
      ],
    );
  }

  // ─ Tab 2: Logout logs ──────────────────────────────────────────────────
  Widget _buildLogoutList() {
    if (_logoutLogs.isEmpty) {
      return _buildEmptyState('No logout records found');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _countBadge(
              '${_logoutLogs.length} Logout Records',
              Icons.logout_rounded,
              _C.purple),
        ),
        ..._logoutLogs.map((r) => _ActivityLogCard(
          record  : r,
          type    : 'logout',
          fmtTs   : _fmtTimestamp,
          fmtDate : _fmtDate,
        )),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _countBadge(String label, IconData icon, Color color) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }

  // ── MOBILE CONTENT ────────────────────────────────────────────────────────
  Widget _buildMobileContent() {
    if (_localRecords.isEmpty) {
      return _buildEmptyState('No attendance records yet');
    }

    final grouped = <String, List<Attendance>>{};
    for (final r in _localRecords) {
      if (r.date.length >= 7) {
        grouped.putIfAbsent(r.date.substring(0, 7), () => []).add(r);
      }
    }

    return RefreshIndicator(
      color: _C.accent,
      backgroundColor: _C.card,
      onRefresh: _sync,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          _buildStatsRow(),
          ...grouped.entries.expand((e) => [
            _buildMonthHeader(e.key, e.value.length),
            ...e.value.map((r) =>
                _MobileAttendanceCard(record: r, fmt12: _fmt12)),
          ]),
        ],
      ),
    );
  }

  Widget _buildMonthHeader(String monthKey, int count) {
    DateTime? dt;
    try { dt = DateTime.parse('$monthKey-01'); } catch (_) {}
    final label =
    dt != null ? DateFormat('MMMM yyyy').format(dt) : monthKey;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _C.white40,
                letterSpacing: 1)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: _C.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$count days',
              style: TextStyle(
                  fontSize: 9,
                  color: _C.accent,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildEmptyState(String msg, {String? subtitle}) =>
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history_rounded, color: _C.white15, size: 56),
          const SizedBox(height: 16),
          Text(msg,
              style: TextStyle(
                  color: _C.white40,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            subtitle ?? 'Records will appear here once available',
            style: TextStyle(
                color: _C.white40.withOpacity(0.6), fontSize: 12),
            textAlign: TextAlign.center,
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _loadData,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _C.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border:
                  Border.all(color: _C.accent.withOpacity(0.3)),
                ),
                child: Text('Refresh',
                    style: TextStyle(
                        color: _C.accent,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// WEB: Paired login+logout card
// ══════════════════════════════════════════════════════════════════════════════
class _CombinedCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final String Function(dynamic) fmtTs;
  final String Function(dynamic) fmtDate;
  final String Function(dynamic, dynamic) durationTs;

  const _CombinedCard({
    required this.record,
    required this.fmtTs,
    required this.fmtDate,
    required this.durationTs,
  });

  @override
  Widget build(BuildContext context) {
    final loginTs   = record['login_ts'];
    final logoutTs  = record['logout_ts'];
    final hasOut    = record['has_out'] == true;
    final empId     = record['employee_id']   as String? ?? '';
    final empName   = record['employee_name'] as String? ?? '';
    final device    = record['device']        as String? ?? '';
    final dateStr   = record['date']          as String? ?? '';
    final dur       = durationTs(loginTs, logoutTs);

    DateTime? dt;
    if (dateStr.isNotEmpty) {
      try { dt = DateTime.parse(dateStr); } catch (_) {}
    } else if (loginTs is Timestamp) {
      dt = loginTs.toDate().toLocal();
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isToday = dateStr == today;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isToday
              ? _C.accent.withOpacity(0.4) : _C.white15,
          width: isToday ? 1.5 : 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          // Date block
          Container(
            width: 52, height: 60,
            decoration: BoxDecoration(
              color: isToday
                  ? _C.accent.withOpacity(0.1) : _C.white08,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isToday
                      ? _C.accent.withOpacity(0.3) : _C.white15),
            ),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dt != null ? DateFormat('EEE').format(dt) : '--',
                    style: TextStyle(
                        fontSize: 9,
                        color: isToday ? _C.accent : _C.white40,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    dt != null ? DateFormat('d').format(dt) : '--',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: isToday ? _C.accent : _C.white),
                  ),
                  Text(
                    dt != null ? DateFormat('MMM').format(dt) : '--',
                    style: TextStyle(
                        fontSize: 9,
                        color: isToday ? _C.accent : _C.white40,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
          ),
          const SizedBox(width: 14),

          // Content
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Employee name / ID
                  if (empName.isNotEmpty)
                    Text(empName,
                        style: const TextStyle(
                            color: _C.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                  if (empId.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(empId,
                        style: TextStyle(
                            fontSize: 10,
                            color: _C.accent,
                            fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 8),

                  // Login → Logout chips
                  Row(children: [
                    _TimeChip(
                        label: 'IN',
                        time: fmtTs(loginTs),
                        color: _C.success),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 12, color: _C.white40),
                    ),
                    _TimeChip(
                        label: 'OUT',
                        time: hasOut ? fmtTs(logoutTs) : 'ACTIVE',
                        color: hasOut ? _C.purple : _C.warning),
                  ]),
                  const SizedBox(height: 8),

                  // Duration + status
                  Row(children: [
                    const Icon(Icons.timer_outlined,
                        size: 11, color: _C.white40),
                    const SizedBox(width: 4),
                    Text(dur,
                        style: TextStyle(
                            fontSize: 11, color: _C.white40)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasOut
                            ? _C.success.withOpacity(0.1)
                            : _C.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        hasOut ? 'COMPLETE' : 'ACTIVE',
                        style: TextStyle(
                            fontSize: 8,
                            color: hasOut ? _C.success : _C.warning,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (device.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(
                        device.toLowerCase().contains('web')
                            ? Icons.computer_rounded
                            : Icons.phone_android_rounded,
                        color: _C.white40,
                        size: 11,
                      ),
                    ],
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WEB: Individual activity_log card (login or logout)
// ══════════════════════════════════════════════════════════════════════════════
class _ActivityLogCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final String type; // 'login' | 'logout'
  final String Function(dynamic) fmtTs;
  final String Function(dynamic) fmtDate;

  const _ActivityLogCard({
    required this.record,
    required this.type,
    required this.fmtTs,
    required this.fmtDate,
  });

  @override
  Widget build(BuildContext context) {
    final isLogin  = type == 'login';
    final color    = isLogin ? _C.success : _C.purple;
    final ts       = record['timestamp'];
    final empId    = (record['employee_id']   ?? '').toString();
    final empName  = (record['employee_name'] ?? '').toString();
    final device   = (record['device']        ?? '').toString();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.white15, width: 0.5),
      ),
      child: Row(children: [
        // Icon badge
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(
            isLogin ? Icons.login_rounded : Icons.logout_rounded,
            color: color, size: 20,
          ),
        ),
        const SizedBox(width: 12),

        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date + time
                Row(children: [
                  Expanded(
                    child: Text(fmtDate(ts),
                        style: const TextStyle(
                            color: _C.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                  Text(fmtTs(ts),
                      style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 5),

                // Employee info + device
                Row(children: [
                  if (empName.isNotEmpty) ...[
                    const Icon(Icons.person_outline_rounded,
                        size: 10, color: _C.white40),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(empName,
                          style: TextStyle(
                              fontSize: 11, color: _C.white70),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (empId.isNotEmpty) ...[
                    const Icon(Icons.badge_outlined,
                        size: 10, color: _C.white40),
                    const SizedBox(width: 4),
                    Text(empId,
                        style: TextStyle(
                            fontSize: 10, color: _C.white40)),
                    const SizedBox(width: 10),
                  ],
                  if (device.isNotEmpty)
                    Row(children: [
                      Icon(
                        device.toLowerCase().contains('web')
                            ? Icons.computer_rounded
                            : Icons.phone_android_rounded,
                        size: 10,
                        color: _C.white40,
                      ),
                      const SizedBox(width: 3),
                      Text(device,
                          style: TextStyle(
                              fontSize: 10, color: _C.white40)),
                    ]),
                ]),
              ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MOBILE: attendance card
// ══════════════════════════════════════════════════════════════════════════════
class _MobileAttendanceCard extends StatelessWidget {
  final Attendance record;
  final String Function(String?) fmt12;
  const _MobileAttendanceCard(
      {required this.record, required this.fmt12});

  @override
  Widget build(BuildContext context) {
    final date    = DateTime.tryParse(record.date);
    final isToday =
        record.date == DateFormat('yyyy-MM-dd').format(DateTime.now());

    Color statusColor;
    switch (record.status) {
      case AttendanceStatus.present: statusColor = _C.success; break;
      case AttendanceStatus.late:    statusColor = _C.warning; break;
      default:                       statusColor = _C.error;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isToday
              ? _C.accent.withOpacity(0.4) : _C.white15,
          width: isToday ? 1.5 : 0.5,
        ),
      ),
      child: Row(children: [
        Container(
          width: 48,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isToday
                ? _C.accent.withOpacity(0.1) : _C.white08,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Text(
              date != null ? DateFormat('EEE').format(date) : '',
              style: TextStyle(
                  fontSize: 9,
                  color: isToday ? _C.accent : _C.white40,
                  fontWeight: FontWeight.w600),
            ),
            Text(
              date != null ? DateFormat('d').format(date) : '--',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isToday ? _C.accent : _C.white),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _TimeChip(
                      label: 'IN',
                      time: fmt12(record.timeIn),
                      color: _C.success),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 11, color: _C.white40)),
                  _TimeChip(
                      label: 'OUT',
                      time: record.timeOut != null
                          ? fmt12(record.timeOut) : 'ACTIVE',
                      color: record.timeOut != null
                          ? _C.purple : _C.warning),
                ]),
                const SizedBox(height: 6),
                Text(record.formattedWorkHours,
                    style: TextStyle(fontSize: 11, color: _C.white40)),
              ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              record.status.label.toUpperCase(),
              style: TextStyle(
                  fontSize: 8,
                  color: statusColor,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared helpers
// ══════════════════════════════════════════════════════════════════════════════
class _TimeChip extends StatelessWidget {
  final String label;
  final String time;
  final Color  color;
  const _TimeChip(
      {required this.label, required this.time, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ',
          style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w800)),
      Text(time,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color)),
    ]),
  );
}

class _StatChip extends StatelessWidget {
  final String   label;
  final String   value;
  final Color    color;
  final IconData icon;
  const _StatChip(
      {required this.label,
        required this.value,
        required this.color,
        required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding:
      const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: color.withOpacity(0.7),
                    fontWeight: FontWeight.w700)),
          ]),
    ),
  );
}