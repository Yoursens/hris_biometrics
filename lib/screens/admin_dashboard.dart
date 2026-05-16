// lib/screens/admin_dashboard.dart
//
// Full Firestore CRUD — employees, activity_logs, user_locations
// All data reads and writes go directly to Firebase Firestore.
// On employee creation → also creates Firebase Auth account.
// Includes one-time backfill for existing employees missing `password`.

import 'dart:async';
import 'dart:math' show cos, sqrt, asin, sin;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show debugPrint;

// ═══════════════════════════════════════════════════════════════════════════
// Bootstrap Design Tokens
// ═══════════════════════════════════════════════════════════════════════════
class BS {
  static const Color primary   = Color(0xFF0D6EFD);
  static const Color secondary = Color(0xFF6C757D);
  static const Color success   = Color(0xFF198754);
  static const Color danger    = Color(0xFFDC3545);
  static const Color warning   = Color(0xFFFFC107);
  static const Color info      = Color(0xFF0DCAF0);
  static const Color light     = Color(0xFFF8F9FA);
  static const Color dark      = Color(0xFF212529);
  static const Color white     = Color(0xFFFFFFFF);
  static const Color muted     = Color(0xFF6C757D);
  static const Color bodyBg    = Color(0xFFF5F6FA);
  static const Color cardBg    = Color(0xFFFFFFFF);
  static const Color border    = Color(0xFFDEE2E6);
  static const Color navBg     = Color(0xFF212529);
  static const Color navText   = Color(0xFFADB5BD);

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 16;
  static const double s4 = 24;
  static const double s5 = 48;

  static const double radiusSm   = 4;
  static const double radius     = 8;
  static const double radiusLg   = 12;
  static const double radiusPill = 50;

  static const double textSm  = 12;
  static const double textBase = 14;
  static const double textLg  = 16;
  static const double textXl  = 20;
  static const double text2xl = 24;

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

// ═══════════════════════════════════════════════════════════════════════════
// Firestore + Auth Service
// ═══════════════════════════════════════════════════════════════════════════
class _DB {
  static final _fs = FirebaseFirestore.instance;

  static CollectionReference get employees    => _fs.collection('employees');
  static CollectionReference get activityLogs => _fs.collection('activity_logs');
  static CollectionReference get locations    => _fs.collection('user_locations');

  static String _msg(Object e) =>
      e is FirebaseException ? (e.message ?? e.toString()) : e.toString();

  // ── READ: employees ───────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getEmployees() async {
    try {
      final s = await employees.orderBy('createdAt', descending: true).get();
      return s.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList();
    } catch (e) { debugPrint('getEmployees: ${_msg(e)}'); return []; }
  }

  // ── READ: logs by type ────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getLogs(String type) async {
    try {
      final s = await activityLogs
          .where('type', isEqualTo: type)
          .orderBy('timestamp', descending: true)
          .get();
      return s.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList();
    } catch (e) { debugPrint('getLogs($type): ${_msg(e)}'); return []; }
  }

  // ── READ: logs by employee ────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getUserLogs(String empId) async {
    try {
      final s = await activityLogs
          .where('employeeId', isEqualTo: empId)
          .orderBy('timestamp', descending: true)
          .get();
      return s.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList();
    } catch (e) { debugPrint('getUserLogs: ${_msg(e)}'); return []; }
  }

  // ── READ: locations ───────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getLocations() async {
    try {
      final s = await locations.get();
      return s.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList();
    } catch (e) { debugPrint('getLocations: ${_msg(e)}'); return []; }
  }

  // ── CREATE: add employee + Firebase Auth account ──────────────────────
  static Future<String?> addEmployee({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String role,
    required String department,
    required String nfcTagId,
    required String pin,
  }) async {
    try {
      // Duplicate NFC check
      final nfcCheck = await employees
          .where('nfcTagId', isEqualTo: nfcTagId.toUpperCase()).get();
      if (nfcCheck.docs.isNotEmpty) {
        return 'A keyfob with serial "$nfcTagId" is already registered.';
      }
      // Duplicate PIN check
      final pinCheck = await employees
          .where('pin', isEqualTo: pin).get();
      if (pinCheck.docs.isNotEmpty) {
        return 'PIN "$pin" is already in use.';
      }

      // ── Create Firebase Auth account ────────────────────────────────
      String authUid = '';
      if (email.isNotEmpty && password.isNotEmpty) {
        try {
          final cred = await FirebaseAuth.instance
              .createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          authUid = cred.user?.uid ?? '';
          debugPrint('Firebase Auth account created: $email');
        } catch (authErr) {
          final code = authErr is FirebaseAuthException
              ? authErr.code : '';
          // If account already exists in Auth, just grab its UID
          if (code == 'email-already-in-use') {
            debugPrint('Auth account already exists for $email — continuing.');
          } else {
            return 'Firebase Auth error: $authErr';
          }
        }
      }

      // ── Save to Firestore ───────────────────────────────────────────
      final docRef = await employees.add({
        'firstName'  : firstName,
        'lastName'   : lastName,
        'name'       : '$firstName $lastName',
        'email'      : email,
        'password'   : password,
        'authUid'    : authUid,
        'role'       : role,
        'department' : department,
        'nfcTagId'   : nfcTagId.toUpperCase(),
        'pin'        : pin,
        'status'     : 'active',
        'createdAt'  : FieldValue.serverTimestamp(),
        'updatedAt'  : FieldValue.serverTimestamp(),
      });

      // Log registration
      await activityLogs.add({
        'type'          : 'registration',
        'employeeId'    : docRef.id,
        'employee_name' : '$firstName $lastName',
        'email'         : email,
        'role'          : role,
        'department'    : department,
        'timestamp'     : FieldValue.serverTimestamp(),
        'device'        : 'Admin Panel',
      });

      return null; // null = success
    } catch (e) {
      return _msg(e);
    }
  }

  // ── UPDATE: employee ──────────────────────────────────────────────────
  static Future<String?> updateEmployee(
      String docId, Map<String, dynamic> data) async {
    try {
      await employees.doc(docId).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) { return _msg(e); }
  }

  // ── DELETE: employee ──────────────────────────────────────────────────
  static Future<String?> deleteEmployee(String docId) async {
    try {
      await employees.doc(docId).delete();
      return null;
    } catch (e) { return _msg(e); }
  }

  // ── DELETE: log entry ─────────────────────────────────────────────────
  static Future<String?> deleteLog(String docId) async {
    try {
      await activityLogs.doc(docId).delete();
      return null;
    } catch (e) { return _msg(e); }
  }

  // ── BACKFILL: add missing `password` field to existing employees ───────
  // Call this once from the dashboard for employees registered before the
  // password field was added. Pass a map of email → password.
  static Future<String?> backfillPasswords(
      Map<String, String> emailToPassword) async {
    try {
      final snap = await employees.get();
      int count = 0;
      for (final doc in snap.docs) {
        final data     = doc.data() as Map<String, dynamic>;
        final email    = (data['email']    ?? '').toString().trim();
        final existing = (data['password'] ?? '').toString().trim();

        if (existing.isNotEmpty) continue; // already has password

        final password = emailToPassword[email];
        if (password == null || password.isEmpty) continue;

        // Update Firestore with password
        await doc.reference.update({'password': password});

        // Also create Firebase Auth account if missing
        String authUid = (data['authUid'] ?? '').toString();
        if (authUid.isEmpty && email.isNotEmpty) {
          try {
            final cred = await FirebaseAuth.instance
                .createUserWithEmailAndPassword(
              email: email,
              password: password,
            );
            authUid = cred.user?.uid ?? '';
            await doc.reference.update({'authUid': authUid});
            debugPrint('Auth account created for $email');
          } catch (authErr) {
            debugPrint('Auth backfill warning for $email: $authErr');
          }
        }
        count++;
        debugPrint('Backfilled password for $email');
      }
      return 'Backfill complete: $count employee(s) updated.';
    } catch (e) {
      return 'Backfill error: ${_msg(e)}';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AdminDashboard
// ═══════════════════════════════════════════════════════════════════════════
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int    _tab    = 0;
  String _search = '';
  final  _searchCtrl = TextEditingController();

  // Add Employee form
  final _fKey        = GlobalKey<FormState>();
  final _firstCtrl   = TextEditingController();
  final _lastCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _roleCtrl    = TextEditingController();
  final _deptCtrl    = TextEditingController();
  final _nfcCtrl     = TextEditingController();
  final _pinCtrl     = TextEditingController();
  final _passCtrl    = TextEditingController();
  bool  _saving      = false;
  bool  _passVisible = false;

  // Edit employee
  Map<String, dynamic>? _editTarget;
  final _editFirstCtrl  = TextEditingController();
  final _editLastCtrl   = TextEditingController();
  final _editRoleCtrl   = TextEditingController();
  final _editDeptCtrl   = TextEditingController();
  final _editEmailCtrl  = TextEditingController();
  final _editPassCtrl   = TextEditingController();
  bool  _editSaving     = false;
  bool  _editPassVisible = false;

  // Backfill dialog controllers
  final _bf1EmailCtrl = TextEditingController();
  final _bf1PassCtrl  = TextEditingController();
  final _bf2EmailCtrl = TextEditingController();
  final _bf2PassCtrl  = TextEditingController();
  final _bf3EmailCtrl = TextEditingController();
  final _bf3PassCtrl  = TextEditingController();

  // Data
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
    _NavItem(2, 'Employees',     Icons.people_rounded),
    _NavItem(3, 'Registrations', Icons.how_to_reg_rounded),
    _NavItem(4, 'Logins',        Icons.vpn_key_rounded),
    _NavItem(5, 'Logouts',       Icons.logout_rounded),
    _NavItem(6, 'Activity',      Icons.view_list_rounded),
    _NavItem(7, 'Tracking',      Icons.my_location_rounded),
  ];

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
    _firstCtrl.dispose(); _lastCtrl.dispose();  _emailCtrl.dispose();
    _roleCtrl.dispose();  _deptCtrl.dispose();  _nfcCtrl.dispose();
    _pinCtrl.dispose();   _passCtrl.dispose();
    _editFirstCtrl.dispose(); _editLastCtrl.dispose();
    _editRoleCtrl.dispose();  _editDeptCtrl.dispose();
    _editEmailCtrl.dispose(); _editPassCtrl.dispose();
    _bf1EmailCtrl.dispose(); _bf1PassCtrl.dispose();
    _bf2EmailCtrl.dispose(); _bf2PassCtrl.dispose();
    _bf3EmailCtrl.dispose(); _bf3PassCtrl.dispose();
    super.dispose();
  }

  // ── Fetch all Firestore data ──────────────────────────────────────────
  Future<void> _fetchAll() async {
    try {
      final results = await Future.wait([
        _DB.getLogs('registration'),
        _DB.getLogs('login'),
        _DB.getLogs('logout'),
        _DB.getEmployees(),
        _DB.getLocations(),
      ]);

      final emps = results[3] as List<Map<String, dynamic>>;
      final Map<String, List<Map<String, dynamic>>> ul = {};
      for (final e in emps) {
        final id = (e['id'] ?? '').toString();
        if (id.isNotEmpty) ul[id] = await _DB.getUserLogs(id);
      }

      if (mounted) setState(() {
        _regLogs    = results[0] as List<Map<String, dynamic>>;
        _loginLogs  = results[1] as List<Map<String, dynamic>>;
        _logoutLogs = results[2] as List<Map<String, dynamic>>;
        _employees  = emps;
        _locations  = results[4] as List<Map<String, dynamic>>;
        _userLogs   = ul;
        _loading    = false;
        _error      = null;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return _splash();
    if (_error != null) return _errorScreen();

    return LayoutBuilder(builder: (_, constraints) {
      final isWide = constraints.maxWidth >= 768;
      return Scaffold(
        backgroundColor: BS.bodyBg,
        appBar: _buildAppBar(isWide),
        drawer: isWide ? null : _buildDrawer(),
        body: isWide
            ? Row(children: [
          _buildSidebar(),
          Expanded(child: _buildPage()),
        ])
            : _buildPage(),
        bottomNavigationBar: isWide ? null : _buildBottomNav(),
      );
    });
  }

  // ── AppBar ────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(bool isWide) => AppBar(
    backgroundColor: BS.navBg,
    foregroundColor: BS.white,
    elevation: 0,
    leading: isWide
        ? Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(Icons.fingerprint, color: BS.primary, size: 28))
        : null,
    title: RichText(text: TextSpan(
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      children: [
        const TextSpan(text: 'HRIS',
            style: TextStyle(color: BS.white)),
        TextSpan(text: ' Biometrics',
            style: TextStyle(
                color: BS.primary, fontWeight: FontWeight.w400)),
      ],
    )),
    actions: [
      // ── Backfill button ─────────────────────────────────────────────
      IconButton(
        icon: const Icon(Icons.build_rounded, size: 20),
        onPressed: _openBackfillDialog,
        tooltip: 'Backfill passwords for existing employees',
      ),
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
          child: const Text('A', style: TextStyle(
              color: BS.white,
              fontWeight: FontWeight.bold,
              fontSize: 13)),
        ),
      ),
    ],
  );

  // ── Backfill dialog ───────────────────────────────────────────────────
  void _openBackfillDialog() {
    // Pre-fill email fields from current employees
    final emails = _employees
        .where((e) => (e['password'] ?? '').toString().isEmpty)
        .map((e) => (e['email'] ?? '').toString())
        .toList();

    if (emails.isNotEmpty) _bf1EmailCtrl.text = emails.elementAtOrNull(0) ?? '';
    if (emails.length > 1) _bf2EmailCtrl.text = emails.elementAtOrNull(1) ?? '';
    if (emails.length > 2) _bf3EmailCtrl.text = emails.elementAtOrNull(2) ?? '';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: BS.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BS.radiusLg)),
          title: Row(children: [
            Icon(Icons.build_rounded, color: BS.warning, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Backfill Passwords',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _infoBox(
                'Enter the password for each existing employee who is '
                    'missing one. Leave blank to skip that employee.',
                BS.warning,
              ),
              const SizedBox(height: BS.s3),
              // Employee 1
              if (emails.isNotEmpty) ...[
                _field(label: 'Email 1', hint: '', ctrl: _bf1EmailCtrl),
                const SizedBox(height: BS.s2),
                _field(label: 'Password 1', hint: '••••••••',
                    ctrl: _bf1PassCtrl, obscure: true,
                    prefixIcon: Icons.lock_outline_rounded),
                const SizedBox(height: BS.s3),
              ],
              // Employee 2
              if (emails.length > 1) ...[
                _field(label: 'Email 2', hint: '', ctrl: _bf2EmailCtrl),
                const SizedBox(height: BS.s2),
                _field(label: 'Password 2', hint: '••••••••',
                    ctrl: _bf2PassCtrl, obscure: true,
                    prefixIcon: Icons.lock_outline_rounded),
                const SizedBox(height: BS.s3),
              ],
              // Employee 3
              if (emails.length > 2) ...[
                _field(label: 'Email 3', hint: '', ctrl: _bf3EmailCtrl),
                const SizedBox(height: BS.s2),
                _field(label: 'Password 3', hint: '••••••••',
                    ctrl: _bf3PassCtrl, obscure: true,
                    prefixIcon: Icons.lock_outline_rounded),
              ],
              if (emails.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: BS.s3),
                  child: Text(
                    '✓ All employees already have passwords set.',
                    style: TextStyle(color: BS.success,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: BS.muted)),
            ),
            if (emails.isNotEmpty)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BS.warning,
                  foregroundColor: BS.dark,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(BS.radius)),
                ),
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Run Backfill',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final map = <String, String>{};
                  if (_bf1EmailCtrl.text.trim().isNotEmpty &&
                      _bf1PassCtrl.text.trim().isNotEmpty) {
                    map[_bf1EmailCtrl.text.trim()] =
                        _bf1PassCtrl.text.trim();
                  }
                  if (_bf2EmailCtrl.text.trim().isNotEmpty &&
                      _bf2PassCtrl.text.trim().isNotEmpty) {
                    map[_bf2EmailCtrl.text.trim()] =
                        _bf2PassCtrl.text.trim();
                  }
                  if (_bf3EmailCtrl.text.trim().isNotEmpty &&
                      _bf3PassCtrl.text.trim().isNotEmpty) {
                    map[_bf3EmailCtrl.text.trim()] =
                        _bf3PassCtrl.text.trim();
                  }
                  if (map.isEmpty) {
                    _snack('No passwords entered.', isError: true);
                    return;
                  }
                  setState(() => _loading = true);
                  final result = await _DB.backfillPasswords(map);
                  await _fetchAll();
                  _snack(result ?? 'Backfill complete!');
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────
  Widget _buildSidebar() => Container(
    width: 230, color: BS.navBg,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.fromLTRB(BS.s3, BS.s3, BS.s3, BS.s2),
        child: Text('NAVIGATION', style: TextStyle(
            color: BS.navText, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ),
      ..._navItems.map(_sidebarTile),
      const Spacer(),
      const Divider(color: Color(0xFF343A40), height: 1),
      Padding(
          padding: const EdgeInsets.all(BS.s3),
          child: Text('Admin Panel v1.0',
              style: TextStyle(color: BS.navText, fontSize: BS.textSm))),
    ]),
  );

  Widget _sidebarTile(_NavItem item) {
    final sel = _tab == item.index;
    return InkWell(
      onTap: () => setState(() => _tab = item.index),
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
          if (item.index == 3 && _regLogs.isNotEmpty)
            _pill(_regLogs.length.toString(), BS.danger),
        ]),
      ),
    );
  }

  Widget _buildDrawer() => Drawer(
    backgroundColor: BS.navBg,
    child: SafeArea(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.all(BS.s3),
          child: Text('HRIS Biometrics', style: TextStyle(
              color: BS.white,
              fontWeight: FontWeight.w700,
              fontSize: 16))),
      const Divider(color: Color(0xFF343A40), height: 1),
      ..._navItems.map((item) => ListTile(
        leading: Icon(item.icon,
            color: _tab == item.index ? BS.primary : BS.navText,
            size: 20),
        title: Text(item.label, style: TextStyle(
            color: _tab == item.index ? BS.white : BS.navText,
            fontSize: BS.textBase)),
        selected: _tab == item.index,
        selectedTileColor: BS.primary.withOpacity(0.2),
        onTap: () {
          setState(() => _tab = item.index);
          Navigator.pop(context);
        },
      )),
    ])),
  );

  Widget _buildBottomNav() => BottomNavigationBar(
    backgroundColor: BS.navBg,
    selectedItemColor: BS.primary,
    unselectedItemColor: BS.navText,
    currentIndex: _tab.clamp(0, 4),
    type: BottomNavigationBarType.fixed,
    selectedFontSize: 10,
    unselectedFontSize: 10,
    onTap: (i) => setState(() => _tab = i),
    items: _navItems.take(5).map((n) => BottomNavigationBarItem(
      icon: Icon(n.icon, size: 22), label: n.label,
    )).toList(),
  );

  // ── Page Router ───────────────────────────────────────────────────────
  Widget _buildPage() {
    switch (_tab) {
      case 0: return _buildOverview();
      case 1: return _buildAddEmployee();
      case 2: return _buildEmployeeList();
      case 3: return _buildLogsPage('Registration Logs', _regLogs,   BS.primary);
      case 4: return _buildLogsPage('Login Logs',        _loginLogs, BS.success);
      case 5: return _buildLogsPage('Logout Logs',       _logoutLogs, BS.warning);
      case 6: return _buildActivity();
      case 7: return _buildTracking();
      default: return _buildOverview();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 0. OVERVIEW
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildOverview() {
    final inRange = _locations.where((l) {
      final lat = (l['latitude']  as num?)?.toDouble();
      final lng = (l['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return false;
      return _haversine(lat, lng, _officeLat, _officeLng) <= _radiusLimit;
    }).length;

    return _pageScroll(title: 'Dashboard', child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (_, c) {
        final cols = c.maxWidth > 500 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: BS.s3, mainAxisSpacing: BS.s3,
          childAspectRatio: c.maxWidth > 500 ? 1.6 : 1.35,
          children: [
            _statCard('Employees',     _employees.length.toString(),
                Icons.people_rounded,      BS.primary),
            _statCard('Registrations', _regLogs.length.toString(),
                Icons.how_to_reg_rounded,  BS.info),
            _statCard('Total Logins',  _loginLogs.length.toString(),
                Icons.vpn_key_rounded,     BS.success),
            _statCard('In Office',     '$inRange',
                Icons.location_on_rounded, BS.warning),
          ],
        );
      }),
      const SizedBox(height: BS.s4),
      _cardSection('Recent Activity', _buildRecentActivity()),
      const SizedBox(height: BS.s4),
      LayoutBuilder(builder: (_, c) {
        if (c.maxWidth > 600) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _cardSection('Latest Logins',
                _miniLogList(_loginLogs.take(4).toList(), BS.success))),
            const SizedBox(width: BS.s3),
            Expanded(child: _cardSection('Latest Logouts',
                _miniLogList(_logoutLogs.take(4).toList(), BS.warning))),
          ]);
        }
        return Column(children: [
          _cardSection('Latest Logins',
              _miniLogList(_loginLogs.take(4).toList(), BS.success)),
          const SizedBox(height: BS.s3),
          _cardSection('Latest Logouts',
              _miniLogList(_logoutLogs.take(4).toList(), BS.warning)),
        ]);
      }),
    ]));
  }

  Widget _statCard(String label, String value, IconData icon, Color color) =>
      Container(
        decoration: BS.card(), padding: const EdgeInsets.all(BS.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(child: Text(label, style: TextStyle(
                    color: BS.muted, fontSize: BS.textSm,
                    fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(BS.radius)),
                  child: Icon(icon, color: color, size: 18),
                ),
              ]),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(color: BS.dark,
                  fontSize: BS.text2xl, fontWeight: FontWeight.w800)),
            ]),
      );

  Widget _miniLogList(
      List<Map<String, dynamic>> logs, Color color) {
    if (logs.isEmpty) return _emptyState('No records');
    return Column(children: logs.map((l) {
      final ts   = l['timestamp'];
      final time = ts is Timestamp
          ? DateFormat('MMM d, h:mm a').format(ts.toDate()) : '—';
      final name = l['employee_name'] ?? l['name'] ??
          l['employeeId'] ?? '—';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(Icons.circle, color: color, size: 8),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: TextStyle(
              color: BS.dark, fontSize: BS.textBase),
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
      final time  = ts is Timestamp
          ? DateFormat('MMM d, h:mm a').format(ts.toDate()) : '—';
      final name  = log['employee_name'] ?? log['name'] ??
          log['employeeId'] ?? '—';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(BS.radius)),
            child: Icon(_kindIcon(kind), color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(color: BS.dark,
                fontSize: BS.textBase, fontWeight: FontWeight.w600)),
            Text(kind.toUpperCase(), style: TextStyle(color: BS.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
          ])),
          Text(time,
              style: TextStyle(color: BS.muted, fontSize: BS.textSm)),
        ]),
      );
    }).toList());
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 1. ADD EMPLOYEE
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildAddEmployee() {
    return _pageScroll(title: 'Add Employee', child: Form(
      key: _fKey,
      child: Container(
        decoration: BS.card(), padding: const EdgeInsets.all(BS.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: BS.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(BS.radius)),
              child: Icon(Icons.person_add_rounded,
                  color: BS.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New Employee', style: TextStyle(
                  color: BS.dark,
                  fontWeight: FontWeight.w700,
                  fontSize: BS.textLg)),
              Text('All starred fields are required',
                  style: TextStyle(
                      color: BS.muted, fontSize: BS.textSm)),
            ]),
          ]),
          const SizedBox(height: BS.s4),
          const Divider(), const SizedBox(height: BS.s3),

          // ── Personal Info ────────────────────────────────────────────
          _sectionHeading('Personal Information'),
          const SizedBox(height: BS.s3),
          _twoCol(
            _field(label: 'First Name *', hint: 'Juan',
                ctrl: _firstCtrl,
                validator: (v) => _req(v, 'First name')),
            _field(label: 'Last Name *', hint: 'Dela Cruz',
                ctrl: _lastCtrl,
                validator: (v) => _req(v, 'Last name')),
          ),
          const SizedBox(height: BS.s3),
          _twoCol(
            _field(
                label: 'Email Address *',
                hint: 'juan@company.com',
                ctrl: _emailCtrl,
                inputType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return 'Email is required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                }),
            _field(label: 'Department *',
                hint: 'e.g. IT, HR, Finance',
                ctrl: _deptCtrl,
                validator: (v) => _req(v, 'Department')),
          ),
          const SizedBox(height: BS.s3),
          _field(label: 'Role / Position *',
              hint: 'e.g. Software Engineer, HR Manager',
              ctrl: _roleCtrl,
              validator: (v) => _req(v, 'Role')),
          const SizedBox(height: BS.s4),

          // ── Biometric Credentials ────────────────────────────────────
          _sectionHeading('Biometric Credentials'),
          const SizedBox(height: BS.s2),
          _infoBox(
            'The keyfob serial and PIN authenticate the employee '
                'at the biometric terminal.',
            BS.info,
          ),
          const SizedBox(height: BS.s3),
          _twoCol(
            _field(
              label: 'Keyfob Serial (NFC) *',
              hint: 'e.g. A1:B2:C3:D4',
              ctrl: _nfcCtrl,
              inputCapitalization: TextCapitalization.characters,
              prefixIcon: Icons.contactless_rounded,
              validator: (v) => _req(v, 'Keyfob serial'),
            ),
            _field(
              label: '4-Digit PIN *',
              hint: '••••',
              ctrl: _pinCtrl,
              obscure: true,
              inputType: TextInputType.number,
              maxLength: 4,
              prefixIcon: Icons.lock_outline_rounded,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly
              ],
              validator: (v) {
                if (v == null || v.isEmpty) return 'PIN is required';
                if (v.length != 4) return 'Must be 4 digits';
                return null;
              },
            ),
          ),
          const SizedBox(height: BS.s3),

          // ── Account Password ─────────────────────────────────────────
          _sectionHeading('Account Password'),
          const SizedBox(height: BS.s2),
          _infoBox(
            'This password is used to create the employee\'s Firebase '
                'Authentication account. They use it to sign in on first login.',
            BS.primary,
          ),
          const SizedBox(height: BS.s3),
          StatefulBuilder(builder: (_, setS) => Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Password *', style: TextStyle(
                  color: BS.dark,
                  fontSize: BS.textBase,
                  fontWeight: FontWeight.w600)),
            ),
            TextFormField(
              controller: _passCtrl,
              obscureText: !_passVisible,
              validator: (v) {
                if (v == null || v.trim().isEmpty)
                  return 'Password is required';
                if (v.trim().length < 6)
                  return 'Minimum 6 characters';
                return null;
              },
              style: TextStyle(color: BS.dark, fontSize: BS.textBase),
              decoration: InputDecoration(
                hintText: '••••••••',
                hintStyle: TextStyle(color: BS.muted),
                prefixIcon: Icon(Icons.lock_rounded,
                    color: BS.muted, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(
                    _passVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: BS.muted, size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _passVisible = !_passVisible),
                ),
                filled: true, fillColor: BS.light,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BS.radius),
                    borderSide: BorderSide(color: BS.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BS.radius),
                    borderSide:
                    BorderSide(color: BS.primary, width: 2)),
                errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BS.radius),
                    borderSide: BorderSide(color: BS.danger)),
                focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BS.radius),
                    borderSide:
                    BorderSide(color: BS.danger, width: 2)),
                errorStyle: TextStyle(
                    color: BS.danger, fontSize: BS.textSm),
              ),
            ),
          ])),
          const SizedBox(height: BS.s4),

          // ── Submit ───────────────────────────────────────────────────
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
              onPressed: _saving ? null : _submitAddEmployee,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: BS.white, strokeWidth: 2))
                  : const Icon(Icons.person_add_rounded, size: 18),
              label: Text(
                  _saving
                      ? 'Creating account…'
                      : 'Save Employee',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ]),
      ),
    ));
  }

  Future<void> _submitAddEmployee() async {
    if (!_fKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final err = await _DB.addEmployee(
      firstName  : _firstCtrl.text.trim(),
      lastName   : _lastCtrl.text.trim(),
      email      : _emailCtrl.text.trim(),
      password   : _passCtrl.text.trim(),
      role       : _roleCtrl.text.trim(),
      department : _deptCtrl.text.trim(),
      nfcTagId   : _nfcCtrl.text.trim(),
      pin        : _pinCtrl.text.trim(),
    );

    setState(() => _saving = false);

    if (err != null) {
      _snack(err, isError: true);
    } else {
      for (final c in [
        _firstCtrl, _lastCtrl, _emailCtrl, _roleCtrl,
        _deptCtrl, _nfcCtrl, _pinCtrl, _passCtrl,
      ]) c.clear();
      _snack('Employee saved & Firebase Auth account created!');
      _fetchAll();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. EMPLOYEE LIST
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildEmployeeList() {
    final filtered = _employees.where((e) => _match(
        '${e['firstName']} ${e['lastName']} ${e['name']} '
            '${e['email']} ${e['role']}')).toList();

    return _pageScroll(title: 'Employees', searchable: true, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(BS.s3),
        decoration: BoxDecoration(
          color: BS.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(BS.radius),
          border: Border.all(color: BS.primary.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(Icons.people_rounded, color: BS.primary, size: 16),
          const SizedBox(width: 8),
          Text('${filtered.length} employee'
              '${filtered.length == 1 ? '' : 's'} found',
              style: TextStyle(color: BS.primary,
                  fontSize: BS.textSm, fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _tab = 1),
            child: _pill('+ Add New', BS.primary),
          ),
        ]),
      ),
      const SizedBox(height: BS.s3),
      if (filtered.isEmpty) _emptyState('No employees found')
      else ...filtered.map((e) => _employeeCard(e)),
    ]));
  }

  Widget _employeeCard(Map<String, dynamic> emp) {
    final first   = emp['firstName'] ?? '';
    final last    = emp['lastName']  ?? '';
    final name    = emp['name'] ?? '$first $last'.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final role    = emp['role']       ?? '—';
    final dept    = emp['department'] ?? '';
    final email   = emp['email']      ?? '';
    final nfc     = emp['nfcTagId']   ?? '—';
    final status  = emp['status']     ?? 'active';
    final docId   = emp['id']         ?? '';
    final hasPwd  = (emp['password']  ?? '').toString().isNotEmpty;

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
                color: BS.primary,
                fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? '—' : name, style: TextStyle(
                color: BS.dark,
                fontWeight: FontWeight.w700,
                fontSize: BS.textLg)),
            Text('$role${dept.isNotEmpty ? ' · $dept' : ''}',
                style: TextStyle(color: BS.muted, fontSize: BS.textSm)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _pill(status, status == 'active' ? BS.success : BS.secondary),
            const SizedBox(height: 4),
            // Show warning badge if password is missing
            if (!hasPwd)
              _pill('No Password', BS.warning),
          ]),
        ]),
        const Divider(height: 20),
        LayoutBuilder(builder: (_, c) {
          final wide = c.maxWidth > 500;
          return wide
              ? Row(children: [
            Expanded(child: _detailItem(
                Icons.email_rounded, 'Email',
                email.isEmpty ? '—' : email)),
            Expanded(child: _detailItem(
                Icons.contactless_rounded, 'NFC', nfc)),
          ])
              : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailItem(Icons.email_rounded, 'Email',
                    email.isEmpty ? '—' : email),
                const SizedBox(height: 8),
                _detailItem(Icons.contactless_rounded,
                    'NFC Keyfob', nfc),
              ]);
        }),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: BS.primary,
              side: BorderSide(color: BS.primary.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BS.radius)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text('Edit',
                style: TextStyle(fontSize: BS.textSm)),
            onPressed: () => _openEditDialog(emp),
          )),
          const SizedBox(width: BS.s2),
          Expanded(child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: BS.danger,
              side: BorderSide(color: BS.danger.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BS.radius)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Delete',
                style: TextStyle(fontSize: BS.textSm)),
            onPressed: () => _confirmDelete(docId, name),
          )),
        ]),
      ]),
    );
  }

  Widget _detailItem(IconData icon, String label, String value) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: BS.muted),
        const SizedBox(width: 6),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: BS.muted, fontSize: 10,
              fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          Text(value,
              style: TextStyle(color: BS.dark, fontSize: BS.textSm),
              overflow: TextOverflow.ellipsis),
        ])),
      ]);

  // ── Edit dialog ───────────────────────────────────────────────────────
  void _openEditDialog(Map<String, dynamic> emp) {
    _editFirstCtrl.text = emp['firstName'] ?? '';
    _editLastCtrl.text  = emp['lastName']  ?? '';
    _editRoleCtrl.text  = emp['role']      ?? '';
    _editDeptCtrl.text  = emp['department']?? '';
    _editEmailCtrl.text = emp['email']     ?? '';
    _editPassCtrl.text  = emp['password']  ?? '';
    setState(() { _editTarget = emp; _editPassVisible = false; });

    showDialog(context: context, builder: (_) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: BS.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BS.radiusLg)),
        title: Text('Edit Employee', style: TextStyle(
            color: BS.dark,
            fontWeight: FontWeight.w800,
            fontSize: BS.textLg)),
        content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
          _twoCol(
            _field(label: 'First Name', hint: '',
                ctrl: _editFirstCtrl),
            _field(label: 'Last Name',  hint: '',
                ctrl: _editLastCtrl),
          ),
          const SizedBox(height: BS.s3),
          _field(label: 'Email', hint: '',
              ctrl: _editEmailCtrl,
              inputType: TextInputType.emailAddress),
          const SizedBox(height: BS.s3),
          _twoCol(
            _field(label: 'Role',       hint: '',
                ctrl: _editRoleCtrl),
            _field(label: 'Department', hint: '',
                ctrl: _editDeptCtrl),
          ),
          const SizedBox(height: BS.s3),
          // Password field in edit dialog
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Password', style: TextStyle(
                  color: BS.dark,
                  fontSize: BS.textBase,
                  fontWeight: FontWeight.w600)),
            ),
            TextFormField(
              controller: _editPassCtrl,
              obscureText: !_editPassVisible,
              style: TextStyle(color: BS.dark, fontSize: BS.textBase),
              decoration: InputDecoration(
                hintText: '••••••••',
                hintStyle: TextStyle(color: BS.muted),
                prefixIcon: Icon(Icons.lock_rounded,
                    color: BS.muted, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(
                    _editPassVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: BS.muted, size: 18,
                  ),
                  onPressed: () =>
                      setS(() => _editPassVisible = !_editPassVisible),
                ),
                filled: true, fillColor: BS.light,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BS.radius),
                    borderSide: BorderSide(color: BS.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BS.radius),
                    borderSide:
                    BorderSide(color: BS.primary, width: 2)),
              ),
            ),
          ]),
        ])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: BS.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BS.primary, foregroundColor: BS.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BS.radius)),
            ),
            onPressed: _editSaving ? null : () async {
              setS(() => _editSaving = true);
              final docId    = (emp['id'] ?? '').toString();
              final first    = _editFirstCtrl.text.trim();
              final last     = _editLastCtrl.text.trim();
              final password = _editPassCtrl.text.trim();

              final updateData = <String, dynamic>{
                'firstName'  : first,
                'lastName'   : last,
                'name'       : '$first $last',
                'email'      : _editEmailCtrl.text.trim(),
                'role'       : _editRoleCtrl.text.trim(),
                'department' : _editDeptCtrl.text.trim(),
              };
              if (password.isNotEmpty) {
                updateData['password'] = password;
              }

              final err = await _DB.updateEmployee(docId, updateData);
              setS(() => _editSaving = false);
              if (!mounted) return;
              Navigator.pop(ctx);
              if (err != null) {
                _snack('Update failed: $err', isError: true);
              } else {
                _snack('Employee updated in Firestore!');
                _fetchAll();
              }
            },
            child: _editSaving
                ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    color: BS.white, strokeWidth: 2))
                : const Text('Save Changes'),
          ),
        ],
      ),
    ));
  }

  // ── Delete confirm ────────────────────────────────────────────────────
  void _confirmDelete(String docId, String name) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: BS.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BS.radiusLg)),
      title: Row(children: [
        Icon(Icons.warning_amber_rounded, color: BS.danger, size: 22),
        const SizedBox(width: 10),
        const Text('Confirm Delete'),
      ]),
      content: Text(
          'Are you sure you want to delete "$name"?\n'
              'This action cannot be undone.',
          style: TextStyle(color: BS.dark, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: BS.muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: BS.danger, foregroundColor: BS.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BS.radius)),
          ),
          onPressed: () async {
            Navigator.pop(context);
            final err = await _DB.deleteEmployee(docId);
            if (err != null) {
              _snack('Delete failed: $err', isError: true);
            } else {
              _snack('Employee deleted from Firestore.');
              _fetchAll();
            }
          },
          child: const Text('Delete'),
        ),
      ],
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3/4/5. LOGS PAGES
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildLogsPage(
      String title, List<Map<String, dynamic>> logs, Color accent) {
    final filtered = _applySearch(logs);
    return _pageScroll(title: title, searchable: true, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          Text('${filtered.length} record'
              '${filtered.length == 1 ? '' : 's'} found',
              style: TextStyle(color: accent,
                  fontSize: BS.textSm, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: BS.s3),
      if (filtered.isEmpty)
        _emptyState('No records found')
      else
        ...filtered.map((l) => _logCard(l, accent)),
    ]));
  }

  Widget _logCard(Map<String, dynamic> log, Color accent) {
    final ts    = log['timestamp'];
    final time  = ts is Timestamp
        ? DateFormat('MMM d, y  h:mm a').format(ts.toDate()) : '—';
    final kind  = log['type']  ?? '';
    final name  = log['employee_name'] ?? log['name'] ??
        log['employeeId'] ?? '—';
    final docId = log['id'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BS.card(), padding: const EdgeInsets.all(BS.s3),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(BS.radius)),
          child: Icon(_kindIcon(kind), color: accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(color: BS.dark,
              fontSize: BS.textBase, fontWeight: FontWeight.w600)),
          Text(log['email'] ?? log['role'] ?? '',
              style: TextStyle(color: BS.muted, fontSize: BS.textSm)),
          Text(time,
              style: TextStyle(color: BS.muted, fontSize: 11)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _pill(kind.toUpperCase(), accent),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () async {
              final err = await _DB.deleteLog(docId);
              if (err != null) {
                _snack('Failed to delete: $err', isError: true);
              } else {
                _snack('Log entry deleted.');
                _fetchAll();
              }
            },
            child: Icon(Icons.delete_outline_rounded,
                color: BS.danger.withOpacity(0.6), size: 18),
          ),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 6. ACTIVITY
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildActivity() {
    final filtered = _employees.where((e) => _match(
        '${e['firstName']} ${e['lastName']} ${e['name']} '
            '${e['employeeId']}')).toList();
    return _pageScroll(title: 'User Activity', searchable: true, child: Column(
      children: filtered.isEmpty
          ? [_emptyState('No employees found')]
          : filtered.map((emp) {
        final id   = (emp['id'] ?? '').toString();
        final logs = _userLogs[id] ?? [];
        return _activityCard(emp, logs);
      }).toList(),
    ));
  }

  Widget _activityCard(
      Map<String, dynamic> emp, List<Map<String, dynamic>> logs) {
    final first   = emp['firstName'] ?? '';
    final last    = emp['lastName']  ?? '';
    final name    = emp['name'] ?? '$first $last'.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final role    = emp['role'] ?? emp['department'] ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BS.card(), padding: const EdgeInsets.all(BS.s3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 22,
              backgroundColor: BS.primary.withOpacity(0.12),
              child: Text(initial, style: TextStyle(
                  color: BS.primary,
                  fontWeight: FontWeight.bold, fontSize: 16))),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? '—' : name, style: TextStyle(
                color: BS.dark,
                fontWeight: FontWeight.w700,
                fontSize: BS.textLg)),
            Text(role,
                style: TextStyle(color: BS.muted, fontSize: BS.textSm)),
          ])),
          _pill('${logs.length} events',
              logs.isEmpty ? BS.secondary : BS.primary),
        ]),
        if (logs.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...logs.take(5).map(_miniRow),
          if (logs.length > 5)
            Padding(padding: const EdgeInsets.only(top: 4),
                child: Text('+${logs.length - 5} more records',
                    style: TextStyle(
                        color: BS.muted, fontSize: 11))),
        ],
      ]),
    );
  }

  Widget _miniRow(Map<String, dynamic> log) {
    final kind  = log['type'] ?? '';
    final color = _kindColor(kind);
    final ts    = log['timestamp'];
    final time  = ts is Timestamp
        ? DateFormat('MMM d, h:mm a').format(ts.toDate()) : '—';
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

  // ═══════════════════════════════════════════════════════════════════════
  // 7. TRACKING
  // ═══════════════════════════════════════════════════════════════════════
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
    final time    = ts is Timestamp
        ? DateFormat('MMM d, y  h:mm a').format(ts.toDate()) : '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BS.card(), padding: const EdgeInsets.all(BS.s3),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(BS.radius)),
          child: Icon(Icons.location_on_rounded, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(loc['name'] ?? loc['employeeId'] ?? '—',
              style: TextStyle(color: BS.dark,
                  fontWeight: FontWeight.w600, fontSize: BS.textBase)),
          Text(dist != null
              ? '${dist.toStringAsFixed(0)} m from office'
              : 'No coordinates',
              style: TextStyle(color: BS.muted, fontSize: BS.textSm)),
          Text(time,
              style: TextStyle(color: BS.muted, fontSize: 11)),
        ])),
        _pill(inRange ? 'In Office' : 'Remote', color),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Layout helpers
  // ═══════════════════════════════════════════════════════════════════════
  Widget _pageScroll({
    required String title,
    required Widget child,
    bool searchable = false,
  }) =>
      SingleChildScrollView(
        padding: const EdgeInsets.all(BS.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(title, style: TextStyle(
                color: BS.dark, fontSize: BS.text2xl,
                fontWeight: FontWeight.w800)),
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
                filled: true, fillColor: BS.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BS.radius),
                    borderSide: BorderSide(color: BS.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BS.radius),
                    borderSide:
                    BorderSide(color: BS.primary, width: 2)),
              ),
            ),
            const SizedBox(height: BS.s3),
          ],
          child,
        ]),
      );

  Widget _cardSection(String title, Widget content) => Container(
    decoration: BS.card(),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(BS.s3, BS.s3, BS.s3, 0),
        child: Text(title, style: TextStyle(
            color: BS.dark,
            fontSize: BS.textLg,
            fontWeight: FontWeight.w700)),
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
      fontWeight: FontWeight.w700, letterSpacing: 0.2));

  Widget _twoCol(Widget a, Widget b) => LayoutBuilder(builder: (_, c) {
    if (c.maxWidth > 500) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: a),
        const SizedBox(width: BS.s3),
        Expanded(child: b),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      a, const SizedBox(height: BS.s3), b,
    ]);
  });

  Widget _field({
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
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: TextStyle(
              color: BS.dark,
              fontSize: BS.textBase,
              fontWeight: FontWeight.w600)),
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
            hintText: hint, hintStyle: TextStyle(color: BS.muted),
            counterText: '',
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: BS.muted, size: 18) : null,
            filled: true, fillColor: BS.light,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 13),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BS.radius),
                borderSide: BorderSide(color: BS.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BS.radius),
                borderSide: BorderSide(color: BS.primary, width: 2)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BS.radius),
                borderSide: BorderSide(color: BS.danger)),
            focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BS.radius),
                borderSide: BorderSide(color: BS.danger, width: 2)),
            errorStyle: TextStyle(
                color: BS.danger, fontSize: BS.textSm),
          ),
        ),
      ]);

  Widget _infoBox(String msg, Color color) => Container(
    padding: const EdgeInsets.all(BS.s3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(BS.radius),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Row(children: [
      Icon(Icons.info_outline, color: color, size: 16),
      const SizedBox(width: 10),
      Expanded(child: Text(msg, style: TextStyle(
          color: BS.dark, fontSize: BS.textSm, height: 1.5))),
    ]),
  );

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(BS.radiusPill),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  Widget _emptyState(String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: BS.s5),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.inbox_rounded, color: BS.border, size: 52),
      const SizedBox(height: 12),
      Text(msg,
          style: TextStyle(color: BS.muted, fontSize: BS.textBase)),
    ])),
  );

  // ── Splash & Error ────────────────────────────────────────────────────
  Widget _splash() => Scaffold(
    backgroundColor: BS.navBg,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.fingerprint, color: BS.primary, size: 72),
      const SizedBox(height: 20),
      const Text('HRIS Biometrics', style: TextStyle(
          color: BS.white, fontSize: 24,
          fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      Text('Loading from Firestore…',
          style: TextStyle(color: BS.navText, fontSize: BS.textBase)),
      const SizedBox(height: 32),
      SizedBox(width: 180, child: LinearProgressIndicator(
          backgroundColor: Colors.white12,
          color: BS.primary,
          borderRadius: BorderRadius.circular(4))),
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
              color: BS.danger.withOpacity(0.1),
              shape: BoxShape.circle),
          child: Icon(Icons.error_outline, color: BS.danger, size: 40),
        ),
        const SizedBox(height: 16),
        Text('Firestore Connection Error', style: TextStyle(
            color: BS.dark,
            fontSize: BS.textXl,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(_error ?? 'Unknown error',
            style: TextStyle(color: BS.muted),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: BS.primary, foregroundColor: BS.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BS.radius)),
            ),
            onPressed: () {
              setState(() { _loading = true; _error = null; });
              _fetchAll();
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry Firestore',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    )),
  );

  // ── Utilities ─────────────────────────────────────────────────────────
  String? _req(String? v, String field) =>
      (v == null || v.trim().isEmpty) ? '$field is required' : null;

  List<Map<String, dynamic>> _applySearch(
      List<Map<String, dynamic>> list) =>
      list.where((e) {
        final q = _search.toLowerCase();
        return q.isEmpty
            || (e['name']          ?? '').toString().toLowerCase().contains(q)
            || (e['employee_name'] ?? '').toString().toLowerCase().contains(q)
            || (e['email']         ?? '').toString().toLowerCase().contains(q)
            || (e['employeeId']    ?? '').toString().toLowerCase().contains(q);
      }).toList();

  bool _match(String s) =>
      _search.isEmpty || s.toLowerCase().contains(_search.toLowerCase());

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

  double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final phi1 = lat1 * 3.141592653589793 / 180;
    final phi2 = lat2 * 3.141592653589793 / 180;
    final dPhi = (lat2 - lat1) * 3.141592653589793 / 180;
    final dLam = (lon2 - lon1) * 3.141592653589793 / 180;
    final a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLam / 2) * sin(dLam / 2);
    return r * 2 * asin(sqrt(a));
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
            isError
                ? Icons.error_outline
                : Icons.check_circle_outline,
            color: BS.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg,
            style: const TextStyle(color: BS.white))),
      ]),
      backgroundColor: isError ? BS.danger : BS.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BS.radius)),
      margin: const EdgeInsets.all(BS.s3),
    ));
  }
}

// ── Nav item model ──────────────────────────────────────────────────────────
class _NavItem {
  final int      index;
  final String   label;
  final IconData icon;
  const _NavItem(this.index, this.label, this.icon);
}