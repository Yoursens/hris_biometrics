// lib/screens/clock_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/geofence_service.dart';
import '../widgets/geofence_indicator.dart';
import '../models/attendance.dart';
import '../models/employee.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Bootstrap design tokens  (mirrors admin_dashboard.dart BS class)
// ═══════════════════════════════════════════════════════════════════════════════
class BS {
  // ── Core palette ──────────────────────────────────────────────────────────
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

  // ── Dark nav surfaces ─────────────────────────────────────────────────────
  static const Color navBg     = Color(0xFF212529);
  static const Color navText   = Color(0xFFADB5BD);
  static const Color border    = Color(0xFFDEE2E6);

  // ── Page / card surfaces ──────────────────────────────────────────────────
  static const Color darkBg    = Color(0xFF060D1F);
  static const Color darkSurf  = Color(0xFF0D1B2E);
  static const Color darkCard  = Color(0xFF0F2040);
  static const Color darkBorder= Color(0xFF1A3356);

  // ── Spacing ($spacer = 16 px) ─────────────────────────────────────────────
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 16;
  static const double s4 = 24;
  static const double s5 = 48;

  // ── Border-radius ─────────────────────────────────────────────────────────
  static const double radiusSm   = 4;
  static const double radius     = 8;
  static const double radiusLg   = 12;
  static const double radiusXl   = 16;
  static const double radiusPill = 50;

  // ── Type scale ────────────────────────────────────────────────────────────
  static const double textXs   = 10;
  static const double textSm   = 12;
  static const double textBase = 14;
  static const double textLg   = 16;
  static const double textXl   = 20;
  static const double text2xl  = 24;

  // ── Dark card decoration ──────────────────────────────────────────────────
  static BoxDecoration darkCardDeco({
    double r = BS.radiusLg,
    Color? borderColor,
  }) =>
      BoxDecoration(
        color: darkCard,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: borderColor ?? darkBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12, offset: const Offset(0, 4),
          ),
        ],
      );

  // ── Badge / pill ──────────────────────────────────────────────────────────
  static Widget badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(BS.radiusPill),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(label, style: TextStyle(
      color: color, fontSize: BS.textXs,
      fontWeight: FontWeight.w700, letterSpacing: 0.5,
    )),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ClockScreen
// ═══════════════════════════════════════════════════════════════════════════════
class ClockScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const ClockScreen({super.key, this.initialEmployee});
  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _successController;
  late AnimationController _ringController;
  late Animation<double>   _pulseAnim;
  late Animation<double>   _successAnim;
  late Animation<double>   _ringAnim;

  Employee?   _employee;
  Attendance? _lastRecord;
  bool   _loading           = true;
  bool   _processing        = false;
  bool   _showSuccess       = false;
  String _successMessage    = '';
  String _successSubMessage = '';
  int    _selectedMethod    = 0;

  GeofenceResult? _geofenceResult;
  late Timer _timer;
  DateTime _now = DateTime.now();
  final _uuid = const Uuid();
  final TextEditingController _pinController = TextEditingController();
  final ScrollController _scrollController  = ScrollController();

  late final List<_ClockMethod> _methods = [
    if (!kIsWeb)
      _ClockMethod(icon: Icons.contactless_rounded,   label: 'NFC Tag',     color: BS.info,     type: AttendanceMethod.nfc),
    _ClockMethod(icon: Icons.face_retouching_natural, label: 'Face ID',     color: BS.primary,  type: AttendanceMethod.face),
    if (!kIsWeb)
      _ClockMethod(icon: Icons.fingerprint_rounded,   label: 'Fingerprint', color: BS.secondary,type: AttendanceMethod.fingerprint),
    _ClockMethod(icon: Icons.pin_rounded,             label: 'PIN',         color: BS.warning,  type: AttendanceMethod.pin),
  ];

  // ── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _pulseController  = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _successController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _ringController   = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();

    _pulseAnim   = Tween<double>(begin: 0.96, end: 1.04)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _successAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _successController, curve: Curves.elasticOut));
    _ringAnim    = Tween<double>(begin: 0.0, end: 1.0).animate(_ringController);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _loadData();
    _checkGeofence();
    if (!kIsWeb) _startNfcSession();
  }

  Future<void> _loadData() async {
    final empId = await SecurityService.instance.getCurrentEmployeeId();
    Employee?   emp;
    Attendance? att;
    if (empId != null && !kIsWeb) {
      emp = await DatabaseService.instance.getEmployeeById(empId);
      att = await DatabaseService.instance.getTodayAttendance(empId);
    }
    emp ??= widget.initialEmployee;
    if (mounted) setState(() { _employee = emp; _lastRecord = att; _loading = false; });
  }

  Future<void> _checkGeofence() async {
    final res = await GeofenceService.instance.checkGeofence();
    if (mounted) setState(() => _geofenceResult = res);
  }

  // ── Interaction Logic ──────────────────────────────────────────────────────
  void _handleClockTap() {
    if (_processing) return;
    final type = _methods[_selectedMethod].type;
    if (type == AttendanceMethod.pin) {
      if (_pinController.text.length == 4) {
        _handlePinSubmit(_pinController.text);
      } else {
        _showSnack('Please enter your 4-digit PIN first', BS.warning);
      }
    } else if (kIsWeb) {
      _showSnack('${_methods[_selectedMethod].label} is only available on Mobile', BS.info);
    } else {
      _showSnack('Please use the sensor to authenticate', BS.primary);
    }
  }

  // ── NFC Session ────────────────────────────────────────────────────────────
  Future<void> _startNfcSession() async {
    if (kIsWeb) return;
    try {
      final isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) return;
      NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
        if (_processing || _showSuccess || (!kIsWeb && _selectedMethod != 0)) return;
        final tagId = _extractTagId(tag);
        if (tagId == null) return;
        if (mounted) setState(() => _processing = true);
        try {
          final employee = await DatabaseService.instance.getEmployeeByNfcTag(tagId);
          if (employee != null) {
            final todayRecord = await DatabaseService.instance.getTodayAttendance(employee.id);
            await _recordAttendance(AttendanceMethod.nfc,
                nfcTagId: tagId, targetEmployee: employee, targetRecord: todayRecord);
          } else {
            _showSnack('Unregistered Tag: $tagId', BS.danger);
            if (mounted) setState(() => _processing = false);
          }
        } catch (e) {
          debugPrint('NFC Error: $e');
          if (mounted) setState(() => _processing = false);
        }
      });
    } catch (e) { debugPrint('NFC session error: $e'); }
  }

  String? _extractTagId(NfcTag tag) {
    try {
      final tagMap = tag.data;
      List<int>? id;
      if (tagMap.containsKey('nfca')) {
        id = tagMap['nfca']['identifier']?.cast<int>();
      } else if (tagMap.containsKey('mifare-classic')) {
        id = tagMap['mifare-classic']['identifier']?.cast<int>();
      }
      if (id == null) return null;
      return id.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
    } catch (_) { return null; }
  }

  Future<void> _handlePinSubmit(String pin) async {
    if (_processing) return;
    setState(() => _processing = true);
    final empId = await SecurityService.instance.getCurrentEmployeeId();
    if (empId == null) {
      _showSnack('Session Error', BS.danger);
      setState(() => _processing = false);
      return;
    }
    final isValid = await SecurityService.instance.verifyPin(empId, pin);
    if (isValid) {
      _pinController.clear();
      await _recordAttendance(AttendanceMethod.pin);
    } else {
      _showSnack('Invalid PIN', BS.danger);
      _pinController.clear();
      setState(() => _processing = false);
    }
  }

  Future<void> _recordAttendance(AttendanceMethod method, {
    String? nfcTagId,
    Employee? targetEmployee,
    Attendance? targetRecord,
  }) async {
    final now     = DateTime.now();
    final today   = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);
    final emp     = targetEmployee ?? _employee;
    if (emp == null) return;
    final record      = targetRecord ?? _lastRecord;
    final isClockedIn = record?.isClockedIn ?? false;
    try {
      if (kIsWeb) {
        await FirebaseFirestore.instance.collection('attendance_logs').add({
          'employee_id'  : emp.employeeId,
          'employee_name': emp.fullName,
          'date'         : today,
          'time'         : timeStr,
          'type'         : isClockedIn ? 'OUT' : 'IN',
          'method'       : method.name,
          'platform'     : 'Web',
          'timestamp'    : FieldValue.serverTimestamp(),
        });
        _showSuccessOverlay(
          isClockedIn ? 'Clock Out Success' : 'Clock In Success',
          '${emp.fullName}\nTime: ${DateFormat('hh:mm a').format(now)}\n(Logged to Cloud)',
        );
      } else {
        if (isClockedIn && record != null) {
          await DatabaseService.instance.updateTimeOut(record.id, timeStr);
          _showSuccessOverlay('Clock Out Success',
              '${emp.fullName}\nTime: ${DateFormat('hh:mm a').format(now)}');
        } else {
          final isLate = now.hour > 9 || (now.hour == 9 && now.minute > 0);
          final attendance = Attendance(
            id         : _uuid.v4(),
            employeeId : emp.id,
            date       : today,
            timeIn     : timeStr,
            status     : isLate ? AttendanceStatus.late : AttendanceStatus.present,
            method     : method,
            createdAt  : now,
            notes      : nfcTagId != null ? 'NFC: $nfcTagId' : null,
          );
          await DatabaseService.instance.logAttendance(attendance);
          _showSuccessOverlay(
            'Clock In Success',
            '${emp.fullName}\nTime: ${DateFormat('hh:mm a').format(now)}'
                '${isLate ? "\n⚠ Late Arrival" : ""}',
          );
        }
      }
      await _loadData();
    } catch (e) {
      _showSnack('Record failed: $e', BS.danger);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showSuccessOverlay(String title, String message) {
    setState(() {
      _showSuccess       = true;
      _successMessage    = title;
      _successSubMessage = message;
    });
    _successController.forward(from: 0);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showSuccess = false);
    });
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          color == BS.danger  ? Icons.error_outline        :
          color == BS.success ? Icons.check_circle_outline :
          Icons.info_outline,
          color: BS.white, size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(
            color: BS.white, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: color == BS.warning ? const Color(0xFF856404) : color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BS.radius)),
      margin: const EdgeInsets.all(BS.s3),
    ));
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pulseController.dispose();
    _successController.dispose();
    _ringController.dispose();
    _pinController.dispose();
    _scrollController.dispose();
    if (!kIsWeb) NfcManager.instance.stopSession();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) return _splash();

    return Scaffold(
      backgroundColor: BS.navBg,
      body: Stack(children: [
        SafeArea(
          child: LayoutBuilder(builder: (ctx, constraints) {
            final isWide = constraints.maxWidth >= 768; // Bootstrap md breakpoint
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 960 : double.infinity),
                child: Column(children: [
                  _buildNavbar(),
                  Expanded(
                    child: Container(
                      color: BS.darkBg,
                      child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
                    ),
                  ),
                ]),
              ),
            );
          }),
        ),
        if (_showSuccess) _buildSuccessOverlay(),
      ]),
    );
  }

  // ── Navbar (.navbar .navbar-dark .bg-dark) ─────────────────────────────────
  Widget _buildNavbar() {
    final emp = _employee;
    return Container(
      height: 56,
      color: BS.navBg,
      padding: const EdgeInsets.symmetric(horizontal: BS.s3),
      child: Row(children: [
        // .navbar-brand
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BS.radiusSm),
              gradient: const LinearGradient(
                colors: [BS.info, BS.primary],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.fingerprint, color: BS.white, size: 16),
          ),
          const SizedBox(width: BS.s2),
          RichText(text: const TextSpan(
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            children: [
              TextSpan(text: 'HRIS', style: TextStyle(color: BS.white)),
              TextSpan(text: ' BIO',
                  style: TextStyle(color: BS.info, fontWeight: FontWeight.w400)),
            ],
          )),
        ]),
        const Spacer(),
        // Date badge → .badge .rounded-pill .border
        Container(
          padding: const EdgeInsets.symmetric(horizontal: BS.s2, vertical: 4),
          decoration: BoxDecoration(
            color: BS.info.withOpacity(0.12),
            borderRadius: BorderRadius.circular(BS.radiusPill),
            border: Border.all(color: BS.info.withOpacity(0.3)),
          ),
          child: Text(
            DateFormat('EEE, MMM d').format(_now).toUpperCase(),
            style: const TextStyle(color: BS.info, fontSize: BS.textXs,
                fontWeight: FontWeight.w700, letterSpacing: 0.8),
          ),
        ),
        const SizedBox(width: BS.s3),
        // Live clock — monospace matches Bootstrap code elements
        Text(DateFormat('hh:mm a').format(_now),
            style: const TextStyle(color: BS.info, fontWeight: FontWeight.w800,
                fontSize: 14, fontFamily: 'monospace')),
        const SizedBox(width: BS.s3),
        // Employee name + avatar
        if (emp != null) ...[
          Column(crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_greeting(), style: const TextStyle(
                    color: BS.navText, fontSize: 9, letterSpacing: 0.5)),
                Text(emp.fullName.split(' ').first.toUpperCase(),
                    style: const TextStyle(color: BS.white,
                        fontWeight: FontWeight.w700, fontSize: 11)),
              ]),
          const SizedBox(width: BS.s2),
          CircleAvatar(
            radius: 17,
            backgroundColor: BS.primary,
            child: Text(
              emp.fullName.isNotEmpty ? emp.fullName[0].toUpperCase() : '?',
              style: const TextStyle(color: BS.white,
                  fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Wide layout ≥ 768 px ──────────────────────────────────────────────────
  Widget _buildWideLayout() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // col-5
      Expanded(
        flex: 5,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BS.s4),
          child: Column(children: [
            _buildGeofenceCard(),
            const SizedBox(height: BS.s3),
            _buildSessionCard(),
            const SizedBox(height: BS.s3),
            _buildClockRing(),
          ]),
        ),
      ),
      Container(width: 1, color: BS.darkBorder.withOpacity(0.5)),
      // col-7
      Expanded(
        flex: 7,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BS.s4),
          child: Column(children: [
            _buildMethodSelector(),
            const SizedBox(height: BS.s3),
            _buildMethodContent(),
          ]),
        ),
      ),
    ]);
  }

  // ── Narrow layout < 768 px ─────────────────────────────────────────────────
  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(BS.s3, BS.s3, BS.s3, BS.s5),
      child: Column(children: [
        _buildGeofenceCard(),
        const SizedBox(height: BS.s3),
        _buildSessionCard(),
        const SizedBox(height: BS.s4),
        _buildClockRing(),
        const SizedBox(height: BS.s4),
        _buildMethodSelector(),
        const SizedBox(height: BS.s3),
        _buildMethodContent(),
      ]),
    );
  }

  // ── Geofence card ──────────────────────────────────────────────────────────
  Widget _buildGeofenceCard() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: BS.s3, vertical: BS.s2 + 2),
      decoration: BS.darkCardDeco(r: BS.radius),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: BS.info.withOpacity(0.12),
            borderRadius: BorderRadius.circular(BS.radius),
          ),
          child: const Icon(Icons.location_on_rounded, color: BS.info, size: 16),
        ),
        const SizedBox(width: BS.s2),
        Expanded(child: GeofenceStatusCard(
          result: _geofenceResult, isLoading: false, onRetry: _checkGeofence,
        )),
      ]),
    );
  }

  // ── Session card (.card .bg-dark) ─────────────────────────────────────────
  Widget _buildSessionCard() {
    final clocked = _lastRecord?.isClockedIn ?? false;
    final timeIn  = _lastRecord?.timeIn;
    final timeOut = _lastRecord?.timeOut;

    String elapsed = '--';
    if (clocked && timeIn != null) {
      try {
        final start = DateTime.parse('${_lastRecord!.date} $timeIn');
        final diff  = _now.difference(start);
        elapsed     = '${diff.inHours}h ${diff.inMinutes % 60}m ${diff.inSeconds % 60}s';
      } catch (_) {}
    }

    return Container(
      decoration: BS.darkCardDeco(
        r: BS.radiusLg,
        borderColor: clocked ? BS.success.withOpacity(0.35) : BS.darkBorder,
      ),
      child: Column(children: [
        // .card-header
        Padding(
          padding: const EdgeInsets.fromLTRB(BS.s3, BS.s3, BS.s3, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TODAY', style: const TextStyle(
                color: BS.navText, fontSize: BS.textXs,
                fontWeight: FontWeight.w700, letterSpacing: 1.5,
              )),
              BS.badge(
                clocked ? '● CLOCKED IN' : '○ NOT IN',
                clocked ? BS.success : BS.danger,
              ),
            ],
          ),
        ),
        const Divider(color: BS.darkBorder, height: 24),
        // .row .g-0 — three cells
        Padding(
          padding: const EdgeInsets.only(bottom: BS.s3),
          child: Row(children: [
            Expanded(child: _sessionCell(Icons.login_rounded,
                'CLOCK IN',  timeIn  != null ? _fmt12(timeIn)  : '--:--', BS.success)),
            Container(width: 1, height: 44, color: BS.darkBorder),
            Expanded(child: _sessionCell(Icons.logout_rounded,
                'CLOCK OUT', timeOut != null ? _fmt12(timeOut) : '--:--', BS.danger)),
            Container(width: 1, height: 44, color: BS.darkBorder),
            Expanded(child: _sessionCell(Icons.timer_rounded,
                'ELAPSED',   elapsed, BS.info)),
          ]),
        ),
      ]),
    );
  }

  Widget _sessionCell(IconData icon, String label, String value, Color color) {
    final hasVal = value != '--:--' && value != '--';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BS.s3),
      child: Column(children: [
        Icon(icon, color: color.withOpacity(0.6), size: 14),
        const SizedBox(height: BS.s1 + 2),
        Text(label, style: const TextStyle(
          color: BS.navText, fontSize: BS.textXs,
          fontWeight: FontWeight.w700, letterSpacing: 1,
        )),
        const SizedBox(height: BS.s1),
        Text(value, style: TextStyle(
          color: hasVal ? BS.white : BS.navText,
          fontSize: BS.textBase - 1,
          fontWeight: FontWeight.w800,
          fontFamily: 'monospace',
        )),
      ]),
    );
  }

  // ── Clock ring (.btn-lg .rounded-circle) ───────────────────────────────────
  Widget _buildClockRing() {
    final clocked   = _lastRecord?.isClockedIn ?? false;
    final ringColor = clocked ? BS.danger : BS.primary;

    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnim, _ringAnim]),
        builder: (_, __) {
          return Transform.scale(
            scale: _pulseAnim.value,
            child: Stack(alignment: Alignment.center, children: [
              // outer glow ring
              Container(
                width: 216, height: 216,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: ringColor.withOpacity(0.12), width: 1),
                ),
              ),
              // spinning arc
              SizedBox(
                width: 200, height: 200,
                child: CircularProgressIndicator(
                  value: _ringAnim.value,
                  strokeWidth: 2,
                  backgroundColor: ringColor.withOpacity(0.07),
                  valueColor: AlwaysStoppedAnimation(
                      ringColor.withOpacity(0.35)),
                ),
              ),
              // main button
              GestureDetector(
                onTap: _handleClockTap,
                child: Container(
                  width: 176, height: 176,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BS.darkCard,
                    border: Border.all(
                        color: ringColor.withOpacity(0.5), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: ringColor.withOpacity(0.22),
                        blurRadius: 32, spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: _processing
                      ? Center(child: CircularProgressIndicator(
                      color: ringColor, strokeWidth: 2.5))
                      : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          clocked ? Icons.logout_rounded
                              : Icons.fingerprint_rounded,
                          size: 46, color: ringColor,
                        ),
                        const SizedBox(height: BS.s2),
                        Text(
                          clocked ? 'CLOCK OUT' : 'CLOCK IN',
                          style: TextStyle(
                            color: ringColor, fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text('TAP TO RECORD',
                            style: TextStyle(
                                color: BS.navText,
                                fontSize: 9, letterSpacing: 1)),
                      ]),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ── Method selector (.btn-group feel) ─────────────────────────────────────
  Widget _buildMethodSelector() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(bottom: BS.s2, left: 2),
        child: Text('AUTHENTICATION METHOD', style: TextStyle(
          color: BS.navText, fontSize: BS.textXs,
          fontWeight: FontWeight.w700, letterSpacing: 1.5,
        )),
      ),
      Row(
        children: _methods.asMap().entries.map((entry) {
          final active = _selectedMethod == entry.key;
          final m      = entry.value;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedMethod = entry.key);
                if (m.type == AttendanceMethod.pin) _scrollToBottom();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: active ? m.color.withOpacity(0.14) : BS.darkCard,
                  borderRadius: BorderRadius.circular(BS.radius),
                  border: Border.all(
                    color: active ? m.color.withOpacity(0.55) : BS.darkBorder,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: active
                          ? m.color.withOpacity(0.18) : BS.darkSurf,
                      borderRadius: BorderRadius.circular(BS.radius),
                    ),
                    child: Icon(m.icon,
                        color: active ? m.color : BS.navText, size: 18),
                  ),
                  const SizedBox(height: BS.s1 + 2),
                  Text(m.label, style: TextStyle(
                    color: active ? m.color : BS.navText,
                    fontSize: BS.textXs,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5,
                  )),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    ]);
  }

  // ── Method content ─────────────────────────────────────────────────────────
  Widget _buildMethodContent() {
    final m = _methods[_selectedMethod];
    if (m.type == AttendanceMethod.pin) return _buildPinInput();

    final msg = m.type == AttendanceMethod.nfc
        ? 'TAP YOUR KEYFOB TO THE BACK OF THE DEVICE'
        : 'AUTHENTICATE USING THE ${m.label.toUpperCase()} SENSOR';

    return Container(
      padding: const EdgeInsets.all(BS.s4),
      decoration: BS.darkCardDeco(
          r: BS.radiusLg, borderColor: m.color.withOpacity(0.2)),
      child: Column(children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
              color: m.color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(m.icon, color: m.color, size: 28),
        ),
        const SizedBox(height: BS.s3),
        Text(msg,
          textAlign: TextAlign.center,
          style: TextStyle(color: m.color, fontWeight: FontWeight.w700,
              fontSize: 11, letterSpacing: 1.2, height: 1.7),
        ),
        const SizedBox(height: BS.s2),
        const Text('Ready and listening…',
            style: TextStyle(color: BS.navText, fontSize: BS.textSm)),
      ]),
    );
  }

  // ── PIN input (.form-control + .btn-warning .btn-lg .w-100) ───────────────
  Widget _buildPinInput() {
    return Container(
      padding: const EdgeInsets.all(BS.s4),
      decoration: BS.darkCardDeco(
          r: BS.radiusLg,
          borderColor: BS.warning.withOpacity(0.25)),
      child: Column(children: [
        // .card-header row
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: BS.warning.withOpacity(0.12),
              borderRadius: BorderRadius.circular(BS.radius),
            ),
            child: const Icon(Icons.pin_rounded, color: BS.warning, size: 18),
          ),
          const SizedBox(width: BS.s2),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PIN Authentication',
                style: TextStyle(color: BS.white,
                    fontWeight: FontWeight.w700, fontSize: BS.textBase)),
            Text('Enter your 4-digit PIN',
                style: TextStyle(color: BS.navText, fontSize: BS.textSm)),
          ]),
        ]),
        const SizedBox(height: BS.s3),
        // .form-control (dark variant)
        TextField(
          controller: _pinController,
          obscureText: true,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 4,
          style: const TextStyle(
            fontSize: 26, letterSpacing: 16,
            color: BS.warning, fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '• • • •',
            hintStyle: TextStyle(
              color: BS.white.withOpacity(0.15),
              letterSpacing: 14, fontSize: 20,
            ),
            filled: true,
            fillColor: BS.darkSurf,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BS.radius),
              borderSide: const BorderSide(color: BS.darkBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BS.radius),
              borderSide: const BorderSide(color: BS.warning, width: 1.5),
            ),
          ),
          onChanged: (val) {
            if (val.length == 4) _handlePinSubmit(val);
          },
        ),
        const SizedBox(height: BS.s3),
        // .btn .btn-warning .btn-lg .w-100
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: BS.warning,
              foregroundColor: BS.dark,
              disabledBackgroundColor: BS.warning.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BS.radius)),
              elevation: 0,
            ),
            onPressed: _processing ? null : () {
              if (_pinController.text.length == 4) {
                _handlePinSubmit(_pinController.text);
              } else {
                _showSnack('Please enter your 4-digit PIN first', BS.warning);
              }
            },
            icon: _processing
                ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    color: BS.dark, strokeWidth: 2))
                : const Icon(Icons.lock_open_rounded, size: 16),
            label: Text(
              _processing ? 'Verifying…' : 'Submit PIN',
              style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: BS.textBase, letterSpacing: 0.5),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Success overlay (.modal .modal-dialog-centered) ────────────────────────
  Widget _buildSuccessOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.80),
        child: Center(
          child: ScaleTransition(
            scale: _successAnim,
            child: Container(
              margin: const EdgeInsets.all(BS.s4),
              padding: const EdgeInsets.symmetric(
                  horizontal: BS.s4, vertical: 36),
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BS.darkCardDeco(
                r: BS.radiusXl + 4,
                borderColor: BS.success.withOpacity(0.4),
              ).copyWith(boxShadow: [
                BoxShadow(color: BS.success.withOpacity(0.14),
                    blurRadius: 40, spreadRadius: 4),
              ]),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: BS.success.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded,
                      color: BS.success, size: 44),
                ),
                const SizedBox(height: BS.s3),
                Text(_successMessage, style: const TextStyle(
                  fontSize: BS.textXl, fontWeight: FontWeight.w800,
                  color: BS.white, letterSpacing: 0.3,
                )),
                const SizedBox(height: BS.s2),
                Text(_successSubMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: BS.navText, height: 1.7,
                        fontSize: BS.textBase)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Splash ─────────────────────────────────────────────────────────────────
  Widget _splash() => Scaffold(
    backgroundColor: BS.navBg,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(BS.radiusLg),
          gradient: const LinearGradient(
            colors: [BS.info, BS.primary],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.fingerprint, color: BS.white, size: 34),
      ),
      const SizedBox(height: BS.s3),
      RichText(text: const TextSpan(
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2),
        children: [
          TextSpan(text: 'HRIS',    style: TextStyle(color: BS.white)),
          TextSpan(text: ' BIO',    style: TextStyle(color: BS.info)),
          TextSpan(text: 'METRICS', style: TextStyle(color: BS.white)),
        ],
      )),
      const SizedBox(height: BS.s1),
      const Text('Loading attendance terminal…',
          style: TextStyle(color: BS.navText, fontSize: BS.textSm)),
      const SizedBox(height: BS.s4),
      SizedBox(
        width: 180,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BS.radiusSm),
          child: const LinearProgressIndicator(
            backgroundColor: BS.darkBorder,
            valueColor: AlwaysStoppedAnimation(BS.primary),
            minHeight: 4,
          ),
        ),
      ),
    ])),
  );

  // ── Utilities ──────────────────────────────────────────────────────────────
  String _fmt12(String t) {
    try { return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t)); }
    catch (_) { return t; }
  }

  String _greeting() {
    final h = _now.hour;
    if (h < 12) return 'Good Morning,';
    if (h < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }
}

class _ClockMethod {
  final IconData icon;
  final String   label;
  final Color    color;
  final AttendanceMethod type;
  _ClockMethod({required this.icon, required this.label,
    required this.color, required this.type});
}