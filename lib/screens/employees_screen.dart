// lib/screens/employees_screen.dart
//
// Employees screen – matches the dark navy dashboard design.
// Pulls employee list from Firestore `employees` collection.
// No `on FirebaseException catch` (Flutter Web safe).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

// ══════════════════════════════════════════════════════════════════════════════
// Design tokens — matches dashboard
// ══════════════════════════════════════════════════════════════════════════════
class _C {
  static const bg        = Color(0xFF0A0F2E);
  static const card      = Color(0xFF0F1535);
  static const cardLight = Color(0xFF131A45);
  static const accent    = Color(0xFF00D4FF);
  static const white     = Color(0xFFFFFFFF);
  static const white70   = Color(0xB3FFFFFF);
  static const white40   = Color(0x66FFFFFF);
  static const white15   = Color(0x26FFFFFF);
  static const white08   = Color(0x14FFFFFF);
  static const success   = Color(0xFF00E5A0);
  static const warning   = Color(0xFFFFBB00);
  static const error     = Color(0xFFFF4D6D);
  static const purple    = Color(0xFF9B6FFF);
  static const orange    = Color(0xFFFF6B35);

  // Avatar palette — cycles through employees
  static const List<Color> avatarColors = [
    Color(0xFF00D4FF),
    Color(0xFF00E5A0),
    Color(0xFF9B6FFF),
    Color(0xFFFFBB00),
    Color(0xFFFF6B35),
    Color(0xFFFF4D6D),
  ];
}

// ══════════════════════════════════════════════════════════════════════════════
// EmployeesScreen widget
// ══════════════════════════════════════════════════════════════════════════════
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen>
    with SingleTickerProviderStateMixin {

  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  bool    _loading = true;
  String? _error;
  String  _search  = '';
  String  _filter  = 'All'; // All | Active | Inactive

  final _searchCtrl = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  static const _filters = ['All', 'Active', 'Inactive'];

  // ── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fetchEmployees();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── data ───────────────────────────────────────────────────────────────────
  Future<void> _fetchEmployees() async {
    setState(() { _loading = true; _error = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .orderBy('createdAt', descending: true)
          .get();
      final list = snap.docs.map((d) => {...d.data(), '_docId': d.id}).toList();
      if (mounted) {
        setState(() {
          _all     = list;
          _loading = false;
        });
        _applyFilter();
        _fadeCtrl.forward(from: 0);
      }
    } catch (e) {
      debugPrint('fetchEmployees: $e');
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    setState(() {
      _filtered = _all.where((emp) {
        // status filter
        if (_filter == 'Active'   && emp['status'] != 'active')   return false;
        if (_filter == 'Inactive' && emp['status'] == 'active')   return false;

        // search filter
        if (q.isEmpty) return true;
        final name  = _fullName(emp).toLowerCase();
        final role  = (emp['role'] ?? emp['department'] ?? '').toString().toLowerCase();
        final email = (emp['email'] ?? '').toString().toLowerCase();
        final nfc   = (emp['nfcTagId'] ?? '').toString().toLowerCase();
        return name.contains(q) || role.contains(q)
            || email.contains(q) || nfc.contains(q);
      }).toList();
    });
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  String _fullName(Map<String, dynamic> emp) {
    final n = emp['name'] ?? '';
    if (n.toString().isNotEmpty) return n.toString();
    final f = emp['firstName'] ?? '';
    final l = emp['lastName']  ?? '';
    return '$f $l'.trim();
  }

  String _initials(Map<String, dynamic> emp) {
    final name = _fullName(emp);
    final parts = name.trim().split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.length == 1 && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return 'EM';
  }

  Color _avatarColor(int index) => _C.avatarColors[index % _C.avatarColors.length];

  bool _isActive(Map<String, dynamic> emp) => emp['status'] == 'active';

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          _buildSearchBar(),
          _buildFilterChips(),
          const SizedBox(height: 4),
          Expanded(child: _buildBody()),
        ]),
      ),
      floatingActionButton: _buildFab(),
    );
  }

  // ── header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final activeCount = _all.where((e) => _isActive(e)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(children: [
        // Title
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Employees', style: TextStyle(
            color: _C.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5,
          )),
          const SizedBox(height: 2),
          Text('${_all.length} total · $activeCount active',
              style: TextStyle(color: _C.white40, fontSize: 13)),
        ])),
        // Refresh
        GestureDetector(
          onTap: _fetchEmployees,
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _C.white08, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.white15),
            ),
            child: Icon(Icons.refresh_rounded, color: _C.accent, size: 20),
          ),
        ),
      ]),
    );
  }

  // ── search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: _C.white08,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.white15),
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) { _search = v; _applyFilter(); },
          style: TextStyle(color: _C.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search by name, role, email…',
            hintStyle: TextStyle(color: _C.white40, fontSize: 13),
            prefixIcon: Icon(Icons.search_rounded, color: _C.white40, size: 20),
            suffixIcon: _search.isNotEmpty
                ? GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                _search = '';
                _applyFilter();
              },
              child: Icon(Icons.close_rounded, color: _C.white40, size: 18),
            )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
    );
  }

  // ── filter chips ───────────────────────────────────────────────────────────
  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(children: _filters.map((f) {
        final sel = _filter == f;
        return GestureDetector(
          onTap: () { setState(() => _filter = f); _applyFilter(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? _C.accent.withOpacity(0.18) : _C.white08,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? _C.accent.withOpacity(0.6) : _C.white15,
              ),
            ),
            child: Text(f, style: TextStyle(
              color: sel ? _C.accent : _C.white40,
              fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
            )),
          ),
        );
      }).toList()),
    );
  }

  // ── body ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_loading) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 28, height: 28,
          child: CircularProgressIndicator(
            color: _C.accent, strokeWidth: 2.5,
          ),
        ),
        const SizedBox(height: 16),
        Text('Loading employees…', style: TextStyle(color: _C.white40, fontSize: 13)),
      ]));
    }

    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _C.error.withOpacity(0.1), shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline_rounded, color: _C.error, size: 36),
          ),
          const SizedBox(height: 14),
          Text('Failed to load employees',
              style: TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: _C.white40, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          _outlineBtn('Retry', Icons.refresh_rounded, _fetchEmployees),
        ]),
      ));
    }

    if (_filtered.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.people_outline_rounded, color: _C.white15, size: 56),
        const SizedBox(height: 14),
        Text(
          _search.isNotEmpty ? 'No results for "$_search"' : 'No employees yet',
          style: TextStyle(color: _C.white40, fontSize: 14),
        ),
        if (_search.isNotEmpty) ...[
          const SizedBox(height: 12),
          _outlineBtn('Clear search', Icons.close_rounded, () {
            _searchCtrl.clear(); _search = ''; _applyFilter();
          }),
        ],
      ]));
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        itemCount: _filtered.length,
        itemBuilder: (_, i) => _employeeCard(_filtered[i], i),
      ),
    );
  }

  // ── employee card ──────────────────────────────────────────────────────────
  Widget _employeeCard(Map<String, dynamic> emp, int index) {
    final name    = _fullName(emp);
    final role    = emp['role'] ?? emp['department'] ?? 'No role';
    final email   = emp['email'] ?? '';
    final active  = _isActive(emp);
    final hasNfc  = (emp['nfcTagId'] ?? '').toString().isNotEmpty;
    final hasPin  = (emp['pin']      ?? '').toString().isNotEmpty;
    final color   = _avatarColor(index);

    return GestureDetector(
      onTap: () => _showEmployeeSheet(emp, index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.white08),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            // Avatar
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.35), width: 1.5),
              ),
              child: Center(child: Text(_initials(emp), style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 16,
              ))),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name.isEmpty ? '—' : name,
                    style: TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 15),
                    overflow: TextOverflow.ellipsis)),
                _statusDot(active),
              ]),
              const SizedBox(height: 3),
              Text(role.toString(), style: TextStyle(color: _C.accent, fontSize: 12,
                  fontWeight: FontWeight.w500)),
              if (email.toString().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(email.toString(),
                    style: TextStyle(color: _C.white40, fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 8),
              // Credential badges
              Row(children: [
                _credBadge(
                  icon: Icons.contactless_rounded,
                  label: 'NFC',
                  active: hasNfc,
                  color: _C.accent,
                ),
                const SizedBox(width: 6),
                _credBadge(
                  icon: Icons.lock_rounded,
                  label: 'PIN',
                  active: hasPin,
                  color: _C.success,
                ),
              ]),
            ])),

            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: _C.white15, size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _statusDot(bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: (active ? _C.success : _C.white40).withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: (active ? _C.success : _C.white40).withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 5, height: 5,
        decoration: BoxDecoration(
          color: active ? _C.success : _C.white40,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 4),
      Text(active ? 'Active' : 'Inactive',
          style: TextStyle(
            color: active ? _C.success : _C.white40,
            fontSize: 10, fontWeight: FontWeight.w700,
          )),
    ]),
  );

  Widget _credBadge({
    required IconData icon,
    required String label,
    required bool active,
    required Color color,
  }) {
    final c = active ? color : _C.white15;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.12) : _C.white08,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active ? color.withOpacity(0.3) : _C.white15),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: c, size: 11),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Employee detail bottom sheet ───────────────────────────────────────────
  void _showEmployeeSheet(Map<String, dynamic> emp, int index) {
    final name   = _fullName(emp);
    final role   = emp['role']  ?? emp['department'] ?? 'No role';
    final email  = emp['email'] ?? '';
    final nfc    = emp['nfcTagId'] ?? '';
    final active = _isActive(emp);
    final color  = _avatarColor(index);
    final ts     = emp['createdAt'];
    String joined = '—';
    if (ts is Timestamp) {
      final d = ts.toDate();
      joined = '${_month(d.month)} ${d.day}, ${d.year}';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: _C.cardLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _C.white08),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
            children: [
              // drag handle
              Center(child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: _C.white15, borderRadius: BorderRadius.circular(2),
                ),
              )),

              // Avatar + name
              Center(child: Column(children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withOpacity(0.5), width: 2),
                  ),
                  child: Center(child: Text(_initials(emp), style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 26,
                  ))),
                ),
                const SizedBox(height: 12),
                Text(name.isEmpty ? '—' : name, style: TextStyle(
                  color: _C.white, fontWeight: FontWeight.w800, fontSize: 20,
                )),
                const SizedBox(height: 4),
                Text(role.toString(), style: TextStyle(color: _C.accent, fontSize: 13)),
                const SizedBox(height: 8),
                _statusDot(active),
              ])),
              const SizedBox(height: 24),

              // Info grid
              _sheetSection('Contact & Info', [
                _sheetRow(Icons.email_outlined,         'Email',    email.toString().isNotEmpty ? email.toString() : '—'),
                _sheetRow(Icons.calendar_today_rounded, 'Joined',   joined),
              ]),
              const SizedBox(height: 16),

              _sheetSection('Credentials', [
                _sheetRow(
                  Icons.contactless_rounded,
                  'Keyfob NFC',
                  nfc.toString().isNotEmpty ? nfc.toString() : 'Not registered',
                  valueColor: nfc.toString().isNotEmpty ? _C.accent : _C.white40,
                ),
                _sheetRow(
                  Icons.lock_rounded,
                  'PIN',
                  (emp['pin'] ?? '').toString().isNotEmpty ? '••••' : 'Not set',
                  valueColor: (emp['pin'] ?? '').toString().isNotEmpty ? _C.success : _C.white40,
                ),
              ]),
              const SizedBox(height: 24),

              // Action buttons
              Row(children: [
                Expanded(child: _sheetBtn(
                  label: active ? 'Deactivate' : 'Activate',
                  icon: active ? Icons.block_rounded : Icons.check_circle_rounded,
                  color: active ? _C.error : _C.success,
                  onTap: () => _toggleStatus(emp),
                )),
                const SizedBox(width: 12),
                Expanded(child: _sheetBtn(
                  label: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  color: _C.error.withOpacity(0.7),
                  onTap: () => _confirmDelete(emp),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetSection(String title, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: TextStyle(
        color: _C.white40, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 1.2,
      )),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.white08),
        ),
        child: Column(children: rows),
      ),
    ],
  );

  Widget _sheetRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: _C.white08, borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _C.accent, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: _C.white40, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(
            color: valueColor ?? _C.white70, fontSize: 13, fontWeight: FontWeight.w600,
          ), overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  Widget _sheetBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            color: color, fontSize: 13, fontWeight: FontWeight.w700,
          )),
        ]),
      ),
    );
  }

  // ── Firestore actions ──────────────────────────────────────────────────────
  Future<void> _toggleStatus(Map<String, dynamic> emp) async {
    Navigator.pop(context);
    final docId  = emp['_docId']?.toString() ?? '';
    final active = _isActive(emp);
    if (docId.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('employees').doc(docId).update({
        'status': active ? 'inactive' : 'active',
      });
      _fetchEmployees();
      _showToast(active ? 'Employee deactivated' : 'Employee activated',
          active ? _C.warning : _C.success);
    } catch (e) {
      _showToast('Failed to update status', _C.error);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> emp) async {
    Navigator.pop(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _C.cardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Employee?', style: TextStyle(
          color: _C.white, fontWeight: FontWeight.w700,
        )),
        content: Text(
          'This will permanently remove ${_fullName(emp)} from the system.',
          style: TextStyle(color: _C.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: _C.white40)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(
              color: _C.error, fontWeight: FontWeight.w700,
            )),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final docId = emp['_docId']?.toString() ?? '';
    if (docId.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('employees').doc(docId).delete();
      _fetchEmployees();
      _showToast('Employee deleted', _C.error);
    } catch (e) {
      _showToast('Failed to delete employee', _C.error);
    }
  }

  // ── FAB ────────────────────────────────────────────────────────────────────
  Widget _buildFab() {
    return GestureDetector(
      onTap: () => _showToast('Use the Admin panel to add employees', _C.accent),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00D4FF), Color(0xFF0055BB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: _C.accent.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Text('Add Employee',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),
    );
  }

  // ── Misc helpers ───────────────────────────────────────────────────────────
  Widget _outlineBtn(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: _C.white08,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.white15),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: _C.accent, size: 16),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: _C.white70, fontSize: 13)),
        ]),
      ),
    );
  }

  void _showToast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color.withOpacity(0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    ));
  }

  String _month(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ][m];
}

// ══════════════════════════════════════════════════════════════════════════════
// Employee data model (unchanged — kept below widget as before)
// ══════════════════════════════════════════════════════════════════════════════
class Employee {
  final String  id;
  final String  employeeId;
  final String  fullName;
  final String  position;
  final String  department;
  final String? email;
  final String? phone;
  final bool    hasFaceEnrolled;
  final bool    hasFingerprintEnrolled;
  final bool    hasPinSet;

  Employee({
    required this.id,
    required this.employeeId,
    required this.fullName,
    required this.position,
    required this.department,
    this.email,
    this.phone,
    this.hasFaceEnrolled = false,
    this.hasFingerprintEnrolled = false,
    this.hasPinSet = false,
  });

  String get initials {
    final parts = fullName.trim().split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return 'EM';
  }

  Employee copyWith({
    String? id, String? employeeId, String? fullName, String? position,
    String? department, String? email, String? phone,
    bool? hasFaceEnrolled, bool? hasFingerprintEnrolled, bool? hasPinSet,
  }) => Employee(
    id: id ?? this.id, employeeId: employeeId ?? this.employeeId,
    fullName: fullName ?? this.fullName, position: position ?? this.position,
    department: department ?? this.department, email: email ?? this.email,
    phone: phone ?? this.phone,
    hasFaceEnrolled: hasFaceEnrolled ?? this.hasFaceEnrolled,
    hasFingerprintEnrolled: hasFingerprintEnrolled ?? this.hasFingerprintEnrolled,
    hasPinSet: hasPinSet ?? this.hasPinSet,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'employeeId': employeeId, 'fullName': fullName,
    'position': position, 'department': department, 'email': email,
    'phone': phone, 'hasFaceEnrolled': hasFaceEnrolled,
    'hasFingerprintEnrolled': hasFingerprintEnrolled, 'hasPinSet': hasPinSet,
  };

  factory Employee.fromMap(Map<String, dynamic> map) => Employee(
    id: map['id']?.toString() ?? '',
    employeeId: map['employeeId']?.toString() ?? '',
    fullName: map['fullName']?.toString() ?? '',
    position: map['position']?.toString() ?? '',
    department: map['department']?.toString() ?? '',
    email: map['email']?.toString(),
    phone: map['phone']?.toString(),
    hasFaceEnrolled: _toBool(map['hasFaceEnrolled']),
    hasFingerprintEnrolled: _toBool(map['hasFingerprintEnrolled']),
    hasPinSet: _toBool(map['hasPinSet']),
  );

  static bool _toBool(dynamic v) {
    if (v is bool)   return v;
    if (v is int)    return v == 1;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return false;
  }
}