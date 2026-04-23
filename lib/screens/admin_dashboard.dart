// lib/screens/admin_dashboard.dart
//
// Responsive Bootstrap-inspired Admin Dashboard
// – Add Employee: firstName, lastName, email, role, nfcTagId (keyfob serial), pin
// – No `on FirebaseException catch` (Flutter Web safe)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'dart:math' show cos, sqrt, asin, sin;
import 'package:flutter/foundation.dart' show debugPrint;

// ═══════════════════════════════════════════════════════════════════════════════
// Bootstrap design tokens
// ═══════════════════════════════════════════════════════════════════════════════
class BS {
  static const Color primary    = Color(0xFF0D6EFD);
  static const Color secondary  = Color(0xFF6C757D);
  static const Color success    = Color(0xFF198754);
  static const Color danger     = Color(0xFFDC3545);
  static const Color warning    = Color(0xFFFFC107);
  static const Color info       = Color(0xFF0DCAF0);
  static const Color light      = Color(0xFFF8F9FA);
  static const Color dark       = Color(0xFF212529);
  static const Color white      = Color(0xFFFFFFFF);
  static const Color muted      = Color(0xFF6C757D);
  static const Color bodyBg     = Color(0xFFF5F6FA);
  static const Color cardBg     = Color(0xFFFFFFFF);
  static const Color border     = Color(0xFFDEE2E6);
  static const Color navBg      = Color(0xFF212529);
  static const Color navText    = Color(0xFFADB5BD);

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 16;
  static const double s4 = 24;
  static const double s5 = 48;

  static const double radiusSm   = 4;
  static const double radius     = 8;
  static const double radiusLg   = 12;
  static const double radiusPill = 50;

  static const double textSm   = 12;
  static const double textBase = 14;
  static const double textLg   = 16;
  static const double textXl   = 20;
  static const double text2xl  = 24;

  static BoxDecoration card({double r = BS.radiusLg}) => BoxDecoration(
    color: cardBg,
    borderRadius: BorderRadius.circular(r),
    border: Border.all(color: border),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.06),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// AdminDashboard
// ═══════════════════════════════════════════════════════════════════════════════
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int    _tabIndex = 0;
  String _search   = '';
  final  _searchCtrl = TextEditingController();

  // ── FIX: controllers and form key lifted here so they survive rebuilds ──
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _roleCtrl      = TextEditingController();
  final _nfcCtrl       = TextEditingController();
  final _pinCtrl       = TextEditingController();
  final _addEmpFormKey = GlobalKey<FormState>();
  bool  _addEmpSaving  = false;

  List<Map<String, dynamic>> _regLogs    = [];
  List<Map<String, dynamic>> _loginLogs  = [];
  List<Map<String, dynamic>> _logoutLogs = [];
  List<Map<String, dynamic>> _employees  = [];
  List<Map<String, dynamic>> _locations  = [];
  Map<String, List<Map<String, dynamic>>> _userLogs = {};

  bool    _loading = true;
  String? _error;
  Timer?  _poll;

  static const double _officeLat   = 14.6114;
  static const double _officeLng   = 120.9936;
  static const double _radiusLimit = 1500.0;

  static const _navItems = [
    _NavItem(0, 'Dashboard',     Icons.dashboard_rounded),
    _NavItem(1, 'Add Employee',  Icons.person_add_rounded),
    _NavItem(2, 'Registrations', Icons.how_to_reg_rounded),
    _NavItem(3, 'Logins',        Icons.vpn_key_rounded),
    _NavItem(4, 'Logouts',       Icons.logout_rounded),
    _NavItem(5, 'Activity',      Icons.view_list_rounded),
    _NavItem(6, 'Tracking',      Icons.my_location_rounded),
  ];

  // ── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fetchAll();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _fetchAll());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _searchCtrl.dispose();
    // ── FIX: dispose the form controllers ──
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _roleCtrl.dispose();
    _nfcCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  // ── Flutter-Web-safe error helper ──────────────────────────────────────────
  String _msg(Object e) {
    if (e is FirebaseException) return e.message ?? e.toString();
    return e.toString();
  }

  // ── Firestore fetch ────────────────────────────────────────────────────────
  Future<void> _fetchAll() async {
    try {
      final r = await Future.wait([
        _fetchLogs('registration'),
        _fetchLogs('login'),
        _fetchLogs('logout'),
        _fetchEmployees(),
        _fetchLocations(),
      ]);
      final emps = r[3] as List<Map<String, dynamic>>;
      final Map<String, List<Map<String, dynamic>>> ul = {};
      for (final e in emps) {
        final id = e['employeeId'] ?? '';
        if (id.isNotEmpty) ul[id] = await _fetchUserLogs(id);
      }
      if (mounted) setState(() {
        _regLogs    = r[0] as List<Map<String, dynamic>>;
        _loginLogs  = r[1] as List<Map<String, dynamic>>;
        _logoutLogs = r[2] as List<Map<String, dynamic>>;
        _employees  = emps;
        _locations  = r[4] as List<Map<String, dynamic>>;
        _userLogs   = ul;
        _loading    = false;
        _error      = null;
      });
    } catch (e) {
      debugPrint('fetchAll: ${_msg(e)}');
      if (mounted) setState(() { _loading = false; _error = _msg(e); });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLogs(String type) async {
    try {
      final s = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('type', isEqualTo: type)
          .orderBy('timestamp', descending: true)
          .get();
      return s.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    } catch (e) { debugPrint('fetchLogs: ${_msg(e)}'); return []; }
  }

  Future<List<Map<String, dynamic>>> _fetchEmployees() async {
    try {
      final s = await FirebaseFirestore.instance.collection('employees').get();
      return s.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    } catch (e) { debugPrint('fetchEmp: ${_msg(e)}'); return []; }
  }

  Future<List<Map<String, dynamic>>> _fetchLocations() async {
    try {
      final s = await FirebaseFirestore.instance.collection('user_locations').get();
      return s.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    } catch (e) { debugPrint('fetchLoc: ${_msg(e)}'); return []; }
  }

  Future<List<Map<String, dynamic>>> _fetchUserLogs(String id) async {
    try {
      final s = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('employeeId', isEqualTo: id)
          .orderBy('timestamp', descending: true)
          .get();
      return s.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    } catch (e) { debugPrint('fetchUL: ${_msg(e)}'); return []; }
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return _splash();
    if (_error != null) return _errorScreen();

    return LayoutBuilder(builder: (ctx, constraints) {
      final isWide = constraints.maxWidth >= 768;
      return Scaffold(
        backgroundColor: BS.bodyBg,
        appBar: _buildAppBar(isWide),
        drawer: isWide ? null : _buildDrawer(),
        body: isWide
            ? Row(children: [_buildSidebar(), Expanded(child: _buildPage())])
            : _buildPage(),
        bottomNavigationBar: isWide ? null : _buildBottomNav(),
      );
    });
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(bool isWide) {
    return AppBar(
      backgroundColor: BS.navBg,
      foregroundColor: BS.white,
      elevation: 0,
      leading: isWide
          ? Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.fingerprint, color: BS.primary, size: 28))
          : null,
      title: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          children: [
            const TextSpan(text: 'HRIS', style: TextStyle(color: BS.white)),
            TextSpan(
              text: ' Biometrics',
              style: TextStyle(color: BS.primary, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: () { setState(() => _loading = true); _fetchAll(); },
          tooltip: 'Refresh',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: BS.primary,
            child: const Text('A',
                style: TextStyle(color: BS.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  // ── Sidebar ────────────────────────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      width: 230,
      color: BS.navBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(BS.s3, BS.s3, BS.s3, BS.s2),
          child: Text('NAVIGATION', style: TextStyle(
            color: BS.navText, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1.5,
          )),
        ),
        ..._navItems.map(_sidebarTile),
        const Spacer(),
        const Divider(color: Color(0xFF343A40), height: 1),
        Padding(
          padding: const EdgeInsets.all(BS.s3),
          child: Text('Admin Panel v1.0',
              style: TextStyle(color: BS.navText, fontSize: BS.textSm)),
        ),
      ]),
    );
  }

  Widget _sidebarTile(_NavItem item) {
    final sel = _tabIndex == item.index;
    return InkWell(
      onTap: () => setState(() => _tabIndex = item.index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? BS.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(BS.radius),
        ),
        child: Row(children: [
          Icon(item.icon, color: sel ? BS.white : BS.navText, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(item.label, style: TextStyle(
            color: sel ? BS.white : BS.navText,
            fontSize: BS.textBase,
            fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
          ))),
          if (item.index == 2 && _regLogs.isNotEmpty)
            _pill(_regLogs.length.toString(), BS.danger),
        ]),
      ),
    );
  }

  // ── Drawer (mobile) ────────────────────────────────────────────────────────
  Widget _buildDrawer() => Drawer(
    backgroundColor: BS.navBg,
    child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.all(BS.s3),
        child: Text('HRIS Biometrics', style: TextStyle(
          color: BS.white, fontWeight: FontWeight.w700, fontSize: 16,
        )),
      ),
      const Divider(color: Color(0xFF343A40), height: 1),
      ..._navItems.map((item) => ListTile(
        leading: Icon(item.icon,
            color: _tabIndex == item.index ? BS.primary : BS.navText, size: 20),
        title: Text(item.label, style: TextStyle(
          color: _tabIndex == item.index ? BS.white : BS.navText,
          fontSize: BS.textBase,
        )),
        selected: _tabIndex == item.index,
        selectedTileColor: BS.primary.withOpacity(0.2),
        onTap: () { setState(() => _tabIndex = item.index); Navigator.pop(context); },
      )),
    ])),
  );

  // ── Bottom Nav (mobile) ────────────────────────────────────────────────────
  Widget _buildBottomNav() => BottomNavigationBar(
    backgroundColor: BS.navBg,
    selectedItemColor: BS.primary,
    unselectedItemColor: BS.navText,
    currentIndex: _tabIndex.clamp(0, 4),
    type: BottomNavigationBarType.fixed,
    selectedFontSize: 10,
    unselectedFontSize: 10,
    onTap: (i) => setState(() => _tabIndex = i),
    items: _navItems.take(5).map((n) => BottomNavigationBarItem(
      icon: Icon(n.icon, size: 22), label: n.label,
    )).toList(),
  );

  // ── Page router ────────────────────────────────────────────────────────────
  Widget _buildPage() {
    switch (_tabIndex) {
      case 0: return _buildOverview();
      case 1: return _buildAddEmployee();
      case 2: return _buildLogsPage('Registration Logs', _regLogs, BS.primary);
      case 3: return _buildLogsPage('Login Logs', _loginLogs, BS.success);
      case 4: return _buildLogsPage('Logout Logs', _logoutLogs, BS.warning);
      case 5: return _buildActivity();
      case 6: return _buildTracking();
      default: return _buildOverview();
    }
  }

  // ── Overview ───────────────────────────────────────────────────────────────
  Widget _buildOverview() {
    final inRange = _locations.where((l) {
      final lat = (l['latitude']  as num?)?.toDouble();
      final lng = (l['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return false;
      return _haversine(lat, lng, _officeLat, _officeLng) <= _radiusLimit;
    }).length;

    return _pageScroll(title: 'Dashboard', child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (_, c) {
          final cols = c.maxWidth > 500 ? 4 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: BS.s3,
            mainAxisSpacing: BS.s3,
            childAspectRatio: c.maxWidth > 500 ? 1.6 : 1.35,
            children: [
              _statCard('Employees',     _employees.length.toString(),  Icons.people_rounded,      BS.primary),
              _statCard('Registrations', _regLogs.length.toString(),    Icons.how_to_reg_rounded,  BS.info),
              _statCard('Total Logins',  _loginLogs.length.toString(),  Icons.vpn_key_rounded,     BS.success),
              _statCard('In Office',     '$inRange',                    Icons.location_on_rounded, BS.warning),
            ],
          );
        }),
        const SizedBox(height: BS.s4),
        _cardSection('Recent Activity', _buildRecentActivity()),
        const SizedBox(height: BS.s4),
        LayoutBuilder(builder: (_, c) {
          if (c.maxWidth > 600) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _cardSection('Latest Logins',  _miniLogList(_loginLogs.take(4).toList(),  BS.success))),
              const SizedBox(width: BS.s3),
              Expanded(child: _cardSection('Latest Logouts', _miniLogList(_logoutLogs.take(4).toList(), BS.warning))),
            ]);
          }
          return Column(children: [
            _cardSection('Latest Logins',  _miniLogList(_loginLogs.take(4).toList(),  BS.success)),
            const SizedBox(height: BS.s3),
            _cardSection('Latest Logouts', _miniLogList(_logoutLogs.take(4).toList(), BS.warning)),
          ]);
        }),
      ],
    ));
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BS.card(),
      padding: const EdgeInsets.all(BS.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: TextStyle(color: BS.muted, fontSize: BS.textSm, fontWeight: FontWeight.w600)),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(BS.radius),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(
            color: BS.dark, fontSize: BS.text2xl, fontWeight: FontWeight.w800,
          )),
        ],
      ),
    );
  }

  Widget _miniLogList(List<Map<String, dynamic>> logs, Color color) {
    if (logs.isEmpty) return _emptyState('No records');
    return Column(children: logs.map((l) {
      final ts   = l['timestamp'];
      final time = ts is Timestamp ? DateFormat('MMM d, h:mm a').format(ts.toDate()) : '—';
      final name = l['employee_name'] ?? l['name'] ?? l['employeeId'] ?? '—';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(Icons.circle, color: color, size: 8),
          const SizedBox(width: 10),
          Expanded(child: Text(name,
              style: TextStyle(color: BS.dark, fontSize: BS.textBase),
              overflow: TextOverflow.ellipsis)),
          Text(time, style: TextStyle(color: BS.muted, fontSize: 11)),
        ]),
      );
    }).toList());
  }

  Widget _buildRecentActivity() {
    final all = [
      ..._loginLogs.map((l)  => {...l, '_kind': 'login'}),
      ..._logoutLogs.map((l) => {...l, '_kind': 'logout'}),
      ..._regLogs.map((l)    => {...l, '_kind': 'registration'}),
    ]..sort((a, b) {
      final ta = a['timestamp']; final tb = b['timestamp'];
      if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
      return 0;
    });
    if (all.isEmpty) return _emptyState('No recent activity');
    return Column(children: all.take(6).map((log) {
      final kind  = log['_kind'] ?? '';
      final color = _kindColor(kind);
      final ts    = log['timestamp'];
      final time  = ts is Timestamp ? DateFormat('MMM d, h:mm a').format(ts.toDate()) : '—';
      final name  = log['employee_name'] ?? log['name'] ?? log['employeeId'] ?? '—';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(BS.radius),
            ),
            child: Icon(_kindIcon(kind), color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(color: BS.dark, fontSize: BS.textBase, fontWeight: FontWeight.w600)),
            Text(kind.toUpperCase(),
                style: TextStyle(color: BS.muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          ])),
          Text(time, style: TextStyle(color: BS.muted, fontSize: BS.textSm)),
        ]),
      );
    }).toList());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADD EMPLOYEE  (firstName, lastName, email, role, nfcTagId, pin)
  // FIX: No local controllers — all controllers live in the State class above
  //      so they are never recreated on rebuild.
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildAddEmployee() {
    return _pageScroll(title: 'Add Employee', child: Form(
      key: _addEmpFormKey,
      child: Container(
        decoration: BS.card(),
        padding: const EdgeInsets.all(BS.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── card header ──────────────────────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: BS.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(BS.radius),
              ),
              child: Icon(Icons.person_add_rounded, color: BS.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New Employee', style: TextStyle(
                color: BS.dark, fontWeight: FontWeight.w700, fontSize: BS.textLg,
              )),
              Text('All starred fields are required',
                  style: TextStyle(color: BS.muted, fontSize: BS.textSm)),
            ]),
          ]),
          const SizedBox(height: BS.s4),
          const Divider(),
          const SizedBox(height: BS.s3),

          // ── section: personal info ────────────────────────────────────
          _sectionHeading('Personal Information'),
          const SizedBox(height: BS.s3),

          LayoutBuilder(builder: (_, c) {
            final wide = c.maxWidth > 500;
            if (wide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _validatedField(
                  label: 'First Name *',
                  hint: 'e.g. Juan',
                  ctrl: _firstNameCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'First name is required' : null,
                )),
                const SizedBox(width: BS.s3),
                Expanded(child: _validatedField(
                  label: 'Last Name *',
                  hint: 'e.g. Dela Cruz',
                  ctrl: _lastNameCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Last name is required' : null,
                )),
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _validatedField(
                label: 'First Name *',
                hint: 'e.g. Juan',
                ctrl: _firstNameCtrl,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'First name is required' : null,
              ),
              const SizedBox(height: BS.s3),
              _validatedField(
                label: 'Last Name *',
                hint: 'e.g. Dela Cruz',
                ctrl: _lastNameCtrl,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Last name is required' : null,
              ),
            ]);
          }),
          const SizedBox(height: BS.s3),

          _validatedField(
            label: 'Email Address',
            hint: 'juan@company.com',
            ctrl: _emailCtrl,
            inputType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null; // optional
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: BS.s3),

          _validatedField(
            label: 'Role in Company *',
            hint: 'e.g. Software Engineer, HR Manager',
            ctrl: _roleCtrl,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Role is required' : null,
          ),
          const SizedBox(height: BS.s4),

          // ── section: biometric credentials ───────────────────────────
          _sectionHeading('Biometric Credentials'),
          const SizedBox(height: BS.s2),
          Container(
            padding: const EdgeInsets.all(BS.s3),
            decoration: BoxDecoration(
              color: BS.info.withOpacity(0.06),
              borderRadius: BorderRadius.circular(BS.radius),
              border: Border.all(color: BS.info.withOpacity(0.25)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: BS.info, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'The keyfob serial number and PIN are used by the login screen '
                    'to authenticate the employee via NFC tap or PIN entry.',
                style: TextStyle(color: BS.dark, fontSize: BS.textSm, height: 1.5),
              )),
            ]),
          ),
          const SizedBox(height: BS.s3),

          LayoutBuilder(builder: (_, c) {
            final wide = c.maxWidth > 500;
            if (wide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _validatedField(
                  label: 'Keyfob Serial Number (NFC) *',
                  hint: 'e.g. A1:B2:C3:D4',
                  ctrl: _nfcCtrl,
                  inputCapitalization: TextCapitalization.characters,
                  prefixIcon: Icons.contactless_rounded,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Keyfob serial is required' : null,
                )),
                const SizedBox(width: BS.s3),
                Expanded(child: _validatedField(
                  label: '4-Digit PIN *',
                  hint: '••••',
                  ctrl: _pinCtrl,
                  obscure: true,
                  inputType: TextInputType.number,
                  maxLength: 4,
                  prefixIcon: Icons.lock_outline_rounded,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'PIN is required';
                    if (v.length != 4) return 'PIN must be exactly 4 digits';
                    return null;
                  },
                )),
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _validatedField(
                label: 'Keyfob Serial Number (NFC) *',
                hint: 'e.g. A1:B2:C3:D4',
                ctrl: _nfcCtrl,
                inputCapitalization: TextCapitalization.characters,
                prefixIcon: Icons.contactless_rounded,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Keyfob serial is required' : null,
              ),
              const SizedBox(height: BS.s3),
              _validatedField(
                label: '4-Digit PIN *',
                hint: '••••',
                ctrl: _pinCtrl,
                obscure: true,
                inputType: TextInputType.number,
                maxLength: 4,
                prefixIcon: Icons.lock_outline_rounded,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'PIN is required';
                  if (v.length != 4) return 'PIN must be exactly 4 digits';
                  return null;
                },
              ),
            ]);
          }),
          const SizedBox(height: BS.s4),

          // ── submit button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: BS.primary,
                foregroundColor: BS.white,
                disabledBackgroundColor: BS.primary.withOpacity(0.6),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(BS.radius)),
                elevation: 0,
              ),
              onPressed: _addEmpSaving ? null : () async {
                if (!_addEmpFormKey.currentState!.validate()) return;
                setState(() => _addEmpSaving = true);
                await _addEmployee(
                  firstName : _firstNameCtrl.text.trim(),
                  lastName  : _lastNameCtrl.text.trim(),
                  email     : _emailCtrl.text.trim(),
                  role      : _roleCtrl.text.trim(),
                  nfcTagId  : _nfcCtrl.text.trim().toUpperCase(),
                  pin       : _pinCtrl.text.trim(),
                );
                setState(() => _addEmpSaving = false);
              },
              icon: _addEmpSaving
                  ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                    color: BS.white, strokeWidth: 2,
                  ))
                  : const Icon(Icons.person_add_rounded, size: 18),
              label: Text(
                _addEmpSaving ? 'Saving…' : 'Add Employee',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ]),
      ),
    ));
  }

  Future<void> _addEmployee({
    required String firstName,
    required String lastName,
    required String email,
    required String role,
    required String nfcTagId,
    required String pin,
  }) async {
    try {
      // Check for duplicate keyfob serial
      final existing = await FirebaseFirestore.instance
          .collection('employees')
          .where('nfcTagId', isEqualTo: nfcTagId)
          .get();
      if (existing.docs.isNotEmpty) {
        _snack('A keyfob with serial "$nfcTagId" is already registered.', isError: true);
        return;
      }

      // Check for duplicate PIN
      final pinCheck = await FirebaseFirestore.instance
          .collection('employees')
          .where('pin', isEqualTo: pin)
          .get();
      if (pinCheck.docs.isNotEmpty) {
        _snack('That PIN is already in use. Please choose a different PIN.', isError: true);
        return;
      }

      await FirebaseFirestore.instance.collection('employees').add({
        'firstName'  : firstName,
        'lastName'   : lastName,
        'name'       : '$firstName $lastName',
        'email'      : email,
        'role'       : role,
        'nfcTagId'   : nfcTagId,
        'pin'        : pin,
        'status'     : 'active',
        'createdAt'  : FieldValue.serverTimestamp(),
        'updatedAt'  : FieldValue.serverTimestamp(),
      });

      // Also log as registration activity
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'type'          : 'registration',
        'employee_name' : '$firstName $lastName',
        'email'         : email,
        'role'          : role,
        'timestamp'     : FieldValue.serverTimestamp(),
        'device'        : 'Admin Panel',
      });

      // Clear all form fields after successful save
      _firstNameCtrl.clear();
      _lastNameCtrl.clear();
      _emailCtrl.clear();
      _roleCtrl.clear();
      _nfcCtrl.clear();
      _pinCtrl.clear();

      _snack('Employee "$firstName $lastName" added successfully!');
      _fetchAll();
    } catch (e) {
      _snack('Error saving employee: ${_msg(e)}', isError: true);
    }
  }

  // ── Logs page ──────────────────────────────────────────────────────────────
  Widget _buildLogsPage(String title, List<Map<String, dynamic>> logs, Color accent) {
    final filtered = _applySearch(logs);
    return _pageScroll(title: title, searchable: true, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(BS.s3),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(BS.radius),
            border: Border.all(color: accent.withOpacity(0.2)),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, color: accent, size: 16),
            const SizedBox(width: 8),
            Text('${filtered.length} record${filtered.length == 1 ? '' : 's'} found',
                style: TextStyle(color: accent, fontSize: BS.textSm, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: BS.s3),
        if (filtered.isEmpty)
          _emptyState('No records found')
        else
          ...filtered.map((l) => _logCard(l, accent)),
      ],
    ));
  }

  Widget _logCard(Map<String, dynamic> log, Color accent) {
    final ts   = log['timestamp'];
    final time = ts is Timestamp ? DateFormat('MMM d, y  h:mm a').format(ts.toDate()) : '—';
    final kind = log['type'] ?? '';
    final name = log['employee_name'] ?? log['name'] ?? log['employeeId'] ?? '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BS.card(),
      padding: const EdgeInsets.all(BS.s3),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(BS.radius),
          ),
          child: Icon(_kindIcon(kind), color: accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(
              color: BS.dark, fontSize: BS.textBase, fontWeight: FontWeight.w600)),
          Text(log['email'] ?? log['role'] ?? '',
              style: TextStyle(color: BS.muted, fontSize: BS.textSm)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _pill(kind.toUpperCase(), accent),
          const SizedBox(height: 4),
          Text(time, style: TextStyle(color: BS.muted, fontSize: 11)),
        ]),
      ]),
    );
  }

  // ── User Activity ──────────────────────────────────────────────────────────
  Widget _buildActivity() {
    final filtered = _employees
        .where((e) => _match('${e['firstName']} ${e['lastName']} ${e['name']} ${e['employeeId']}'))
        .toList();
    return _pageScroll(title: 'User Activity', searchable: true, child: Column(
      children: filtered.isEmpty
          ? [_emptyState('No employees found')]
          : filtered.map((emp) {
        final id   = emp['employeeId'] ?? emp['id'] ?? '';
        final logs = _userLogs[id] ?? [];
        return _activityCard(emp, logs);
      }).toList(),
    ));
  }

  Widget _activityCard(Map<String, dynamic> emp, List<Map<String, dynamic>> logs) {
    final first   = emp['firstName'] ?? '';
    final last    = emp['lastName']  ?? '';
    final name    = emp['name'] ?? '$first $last'.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final role    = emp['role'] ?? emp['department'] ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BS.card(),
      padding: const EdgeInsets.all(BS.s3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: BS.primary.withOpacity(0.12),
            child: Text(initial, style: TextStyle(
              color: BS.primary, fontWeight: FontWeight.bold, fontSize: 16,
            )),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? '—' : name,
                style: TextStyle(color: BS.dark, fontWeight: FontWeight.w700, fontSize: BS.textLg)),
            Text(role, style: TextStyle(color: BS.muted, fontSize: BS.textSm)),
          ])),
          _pill('${logs.length} events', logs.isEmpty ? BS.secondary : BS.primary),
        ]),
        if (logs.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...logs.take(5).map(_miniRow),
          if (logs.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+${logs.length - 5} more records',
                  style: TextStyle(color: BS.muted, fontSize: 11)),
            ),
        ],
      ]),
    );
  }

  Widget _miniRow(Map<String, dynamic> log) {
    final kind  = log['type'] ?? '';
    final color = _kindColor(kind);
    final ts    = log['timestamp'];
    final time  = ts is Timestamp ? DateFormat('MMM d, h:mm a').format(ts.toDate()) : '—';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(_kindIcon(kind), color: color, size: 14),
        const SizedBox(width: 8),
        _pill(kind.toUpperCase(), color),
        const Spacer(),
        Text(time, style: TextStyle(color: BS.muted, fontSize: 11)),
      ]),
    );
  }

  // ── Live Tracking ──────────────────────────────────────────────────────────
  Widget _buildTracking() {
    final filtered = _locations
        .where((l) => _match('${l['name']} ${l['employeeId']}'))
        .toList();
    return _pageScroll(title: 'Live Tracking', searchable: true, child: Column(
      children: filtered.isEmpty
          ? [_emptyState('No location data available')]
          : filtered.map(_trackCard).toList(),
    ));
  }

  Widget _trackCard(Map<String, dynamic> loc) {
    final lat     = (loc['latitude']  as num?)?.toDouble();
    final lng     = (loc['longitude'] as num?)?.toDouble();
    final dist    = lat != null && lng != null
        ? _haversine(lat, lng, _officeLat, _officeLng) : null;
    final inRange = dist != null && dist <= _radiusLimit;
    final color   = inRange ? BS.success : BS.danger;
    final ts      = loc['timestamp'];
    final time    = ts is Timestamp ? DateFormat('MMM d, y  h:mm a').format(ts.toDate()) : '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BS.card(),
      padding: const EdgeInsets.all(BS.s3),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(BS.radius),
          ),
          child: Icon(Icons.location_on_rounded, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(loc['name'] ?? loc['employeeId'] ?? '—',
              style: TextStyle(color: BS.dark, fontWeight: FontWeight.w600, fontSize: BS.textBase)),
          Text(
            dist != null ? '${dist.toStringAsFixed(0)} m from office' : 'No coordinates',
            style: TextStyle(color: BS.muted, fontSize: BS.textSm),
          ),
          Text(time, style: TextStyle(color: BS.muted, fontSize: 11)),
        ])),
        _pill(inRange ? 'In Office' : 'Remote', color),
      ]),
    );
  }

  // ── Layout helpers ─────────────────────────────────────────────────────────
  Widget _pageScroll({
    required String title,
    required Widget child,
    bool searchable = false,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BS.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: TextStyle(
            color: BS.dark, fontSize: BS.text2xl, fontWeight: FontWeight.w800,
          )),
          Text(DateFormat('MMM d, y').format(DateTime.now()),
              style: TextStyle(color: BS.muted, fontSize: BS.textSm)),
        ]),
        const SizedBox(height: BS.s3),
        if (searchable) ...[
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
            style: TextStyle(color: BS.dark, fontSize: BS.textBase),
            decoration: InputDecoration(
              hintText: 'Search…',
              hintStyle: TextStyle(color: BS.muted),
              prefixIcon: Icon(Icons.search, color: BS.muted, size: 18),
              filled: true,
              fillColor: BS.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BS.radius),
                borderSide: BorderSide(color: BS.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BS.radius),
                borderSide: BorderSide(color: BS.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: BS.s3),
        ],
        child,
      ]),
    );
  }

  Widget _cardSection(String title, Widget content) => Container(
    decoration: BS.card(),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(BS.s3, BS.s3, BS.s3, 0),
        child: Text(title, style: TextStyle(
          color: BS.dark, fontSize: BS.textLg, fontWeight: FontWeight.w700,
        )),
      ),
      const Divider(height: 24),
      Padding(
        padding: const EdgeInsets.fromLTRB(BS.s3, 0, BS.s3, BS.s3),
        child: content,
      ),
    ]),
  );

  Widget _sectionHeading(String t) => Text(t, style: TextStyle(
    color: BS.dark, fontSize: BS.textBase,
    fontWeight: FontWeight.w700, letterSpacing: 0.2,
  ));

  Widget _validatedField({
    required String label,
    required String hint,
    required TextEditingController ctrl,
    String? Function(String?)? validator,
    TextInputType inputType = TextInputType.text,
    TextCapitalization inputCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    bool obscure = false,
    int? maxLength,
    IconData? prefixIcon,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label, style: TextStyle(
          color: BS.dark, fontSize: BS.textBase, fontWeight: FontWeight.w600,
        )),
      ),
      TextFormField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: inputType,
        textCapitalization: inputCapitalization,
        inputFormatters: inputFormatters,
        maxLength: maxLength,
        validator: validator,
        style: TextStyle(color: BS.dark, fontSize: BS.textBase),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: BS.muted),
          counterText: '',
          prefixIcon: prefixIcon != null
              ? Icon(prefixIcon, color: BS.muted, size: 18) : null,
          filled: true,
          fillColor: BS.light,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BS.radius),
            borderSide: BorderSide(color: BS.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BS.radius),
            borderSide: BorderSide(color: BS.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BS.radius),
            borderSide: BorderSide(color: BS.danger),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BS.radius),
            borderSide: BorderSide(color: BS.danger, width: 2),
          ),
          errorStyle: TextStyle(color: BS.danger, fontSize: BS.textSm),
        ),
      ),
    ]);
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(BS.radiusPill),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(
      color: color, fontSize: 11, fontWeight: FontWeight.w700,
    )),
  );

  Widget _emptyState(String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: BS.s5),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.inbox_rounded, color: BS.border, size: 52),
      const SizedBox(height: 12),
      Text(msg, style: TextStyle(color: BS.muted, fontSize: BS.textBase)),
    ])),
  );

  // ── Splash & Error ─────────────────────────────────────────────────────────
  Widget _splash() => Scaffold(
    backgroundColor: BS.navBg,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.fingerprint, color: BS.primary, size: 72),
      const SizedBox(height: 20),
      const Text('HRIS Biometrics', style: TextStyle(
        color: BS.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1.2,
      )),
      const SizedBox(height: 8),
      Text('Loading admin panel…', style: TextStyle(color: BS.navText, fontSize: BS.textBase)),
      const SizedBox(height: 32),
      SizedBox(
        width: 180,
        child: LinearProgressIndicator(
          backgroundColor: Colors.white12,
          color: BS.primary,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    ])),
  );

  Widget _errorScreen() => Scaffold(
    backgroundColor: BS.bodyBg,
    body: Center(child: Container(
      margin: const EdgeInsets.all(BS.s4),
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(BS.s4),
      decoration: BS.card(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: BS.danger.withOpacity(0.1), shape: BoxShape.circle,
          ),
          child: Icon(Icons.error_outline, color: BS.danger, size: 40),
        ),
        const SizedBox(height: 16),
        Text('Connection Error', style: TextStyle(
          color: BS.dark, fontSize: BS.textXl, fontWeight: FontWeight.w700,
        )),
        const SizedBox(height: 8),
        Text(_error ?? 'Unknown error',
            style: TextStyle(color: BS.muted), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: BS.primary, foregroundColor: BS.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BS.radius)),
            ),
            onPressed: () {
              setState(() { _loading = true; _error = null; });
              _fetchAll();
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    )),
  );

  // ── Utilities ──────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _applySearch(List<Map<String, dynamic>> list) =>
      list.where((e) {
        final q = _search.toLowerCase();
        return q.isEmpty
            || (e['name']          ?? '').toString().toLowerCase().contains(q)
            || (e['employee_name'] ?? '').toString().toLowerCase().contains(q)
            || (e['email']         ?? '').toString().toLowerCase().contains(q)
            || (e['employeeId']    ?? '').toString().toLowerCase().contains(q);
      }).toList();

  bool _match(String s) {
    final q = _search.toLowerCase();
    return q.isEmpty || s.toLowerCase().contains(q);
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'login':        return Icons.vpn_key_rounded;
      case 'logout':       return Icons.logout_rounded;
      case 'registration': return Icons.how_to_reg_rounded;
      default:             return Icons.circle_outlined;
    }
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'login':        return BS.success;
      case 'logout':       return BS.warning;
      case 'registration': return BS.primary;
      default:             return BS.secondary;
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final phi1 = lat1 * 3.141592653589793 / 180;
    final phi2 = lat2 * 3.141592653589793 / 180;
    final dPhi = (lat2 - lat1) * 3.141592653589793 / 180;
    final dLam = (lon2 - lon1) * 3.141592653589793 / 180;
    final a = sin(dPhi/2)*sin(dPhi/2) + cos(phi1)*cos(phi2)*sin(dLam/2)*sin(dLam/2);
    return r * 2 * asin(sqrt(a));
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          isError ? Icons.error_outline : Icons.check_circle_outline,
          color: BS.white, size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(color: BS.white))),
      ]),
      backgroundColor: isError ? BS.danger : BS.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BS.radius)),
      margin: const EdgeInsets.all(BS.s3),
    ));
  }
}

// ── Nav item model ─────────────────────────────────────────────────────────────
class _NavItem {
  final int      index;
  final String   label;
  final IconData icon;
  const _NavItem(this.index, this.label, this.icon);
}