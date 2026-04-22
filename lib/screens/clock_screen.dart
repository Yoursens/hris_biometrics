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
  late Animation<double>   _pulseAnim;
  late Animation<double>   _successAnim;

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
  final ScrollController _scrollController = ScrollController();

  late final List<_ClockMethod> _methods = [
    if (!kIsWeb) 
      _ClockMethod(icon: Icons.contactless_rounded, label: 'NFC Tag', color: AppColors.accentSecondary, type: AttendanceMethod.nfc),
    _ClockMethod(icon: Icons.face_retouching_natural, label: 'Face ID', color: AppColors.accent, type: AttendanceMethod.face),
    if (!kIsWeb)
      _ClockMethod(icon: Icons.fingerprint_rounded, label: 'Fingerprint', color: AppColors.accentSecondary, type: AttendanceMethod.fingerprint),
    _ClockMethod(icon: Icons.pin_rounded, label: 'PIN', color: AppColors.warning, type: AttendanceMethod.pin),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _successController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _successAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _successController, curve: Curves.elasticOut));
    
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _loadData();
    _checkGeofence();
    if (!kIsWeb) _startNfcSession();
  }

  Future<void> _loadData() async {
    final empId = await SecurityService.instance.getCurrentEmployeeId();
    
    Employee? emp;
    Attendance? att;

    if (empId != null && !kIsWeb) {
      emp = await DatabaseService.instance.getEmployeeById(empId);
      att = await DatabaseService.instance.getTodayAttendance(empId);
    }

    emp ??= widget.initialEmployee;

    if (mounted) {
      setState(() {
        _employee = emp;
        _lastRecord = att;
        _loading = false;
      });
    }
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
        _showSnack('Please enter your 4-digit PIN first', AppColors.warning);
      }
    } else if (kIsWeb) {
      _showSnack('${_methods[_selectedMethod].label} is only available on Mobile', AppColors.info);
    } else {
      // Mobile biometric / NFC handled by their own logic or triggers
      _showSnack('Please use the sensor to authenticate', AppColors.accent);
    }
  }

  // ── NFC Session ────────────────────────────────────────────────────────────
  Future<void> _startNfcSession() async {
    if (kIsWeb) return;
    try {
      final isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) return;

      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          if (_processing || _showSuccess || (!kIsWeb && _selectedMethod != 0)) return;
          
          final tagId = _extractTagId(tag);
          if (tagId == null) return;

          if (mounted) setState(() => _processing = true);

          try {
            final employee = await DatabaseService.instance.getEmployeeByNfcTag(tagId);
            if (employee != null) {
              final todayRecord = await DatabaseService.instance.getTodayAttendance(employee.id);
              await _recordAttendance(AttendanceMethod.nfc, nfcTagId: tagId, targetEmployee: employee, targetRecord: todayRecord);
            } else {
              _showSnack('Unregistered Tag: $tagId', AppColors.error);
              if (mounted) setState(() => _processing = false);
            }
          } catch (e) {
            debugPrint('NFC Error: $e');
            if (mounted) setState(() => _processing = false);
          }
        },
      );
    } catch (e) {
      debugPrint('NFC session error: $e');
    }
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
      _showSnack('Session Error', AppColors.error);
      setState(() => _processing = false);
      return;
    }

    final isValid = await SecurityService.instance.verifyPin(empId, pin);
    if (isValid) {
      _pinController.clear();
      await _recordAttendance(AttendanceMethod.pin);
    } else {
      _showSnack('Invalid PIN', AppColors.error);
      _pinController.clear();
      setState(() => _processing = false);
    }
  }

  Future<void> _recordAttendance(AttendanceMethod method, {
    String? nfcTagId, 
    Employee? targetEmployee, 
    Attendance? targetRecord
  }) async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);
    
    final emp = targetEmployee ?? _employee;
    if (emp == null) return;

    final record = targetRecord ?? _lastRecord;
    final isClockedIn = record?.isClockedIn ?? false;

    try {
      if (kIsWeb) {
        // Log to Firestore for Web
        await FirebaseFirestore.instance.collection('attendance_logs').add({
          'employee_id': emp.employeeId,
          'employee_name': emp.fullName,
          'date': today,
          'time': timeStr,
          'type': isClockedIn ? 'OUT' : 'IN',
          'method': method.name,
          'platform': 'Web',
          'timestamp': FieldValue.serverTimestamp(),
        });
        
        _showSuccessOverlay(
          isClockedIn ? 'Clock Out Success' : 'Clock In Success', 
          '${emp.fullName}\nTime: ${DateFormat('hh:mm a').format(now)}\n(Logged to Cloud)'
        );
      } else {
        // Mobile logic
        if (isClockedIn && record != null) {
          await DatabaseService.instance.updateTimeOut(record.id, timeStr);
          _showSuccessOverlay('Clock Out Success', '${emp.fullName}\nTime: ${DateFormat('hh:mm a').format(now)}');
        } else {
          final isLate = now.hour > 9 || (now.hour == 9 && now.minute > 0);
          final attendance = Attendance(
            id: _uuid.v4(),
            employeeId: emp.id,
            date: today,
            timeIn: timeStr,
            status: isLate ? AttendanceStatus.late : AttendanceStatus.present,
            method: method,
            createdAt: now,
            notes: nfcTagId != null ? 'NFC: $nfcTagId' : null,
          );
          await DatabaseService.instance.logAttendance(attendance);
          _showSuccessOverlay('Clock In Success', '${emp.fullName}\nTime: ${DateFormat('hh:mm a').format(now)}${isLate ? "\n⚠ Late Arrival" : ""}');
        }
      }
      await _loadData();
    } catch (e) {
      _showSnack('Record failed: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showSuccessOverlay(String title, String message) {
    setState(() {
      _showSuccess = true;
      _successMessage = title;
      _successSubMessage = message;
    });
    _successController.forward(from: 0);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showSuccess = false);
    });
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
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
    _pinController.dispose();
    _scrollController.dispose();
    if (!kIsWeb) NfcManager.instance.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.primary, body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          LayoutBuilder(builder: (context, constraints) {
            bool isWide = constraints.maxWidth > 900;
            return Center(
              child: Container(
                constraints: BoxConstraints(maxWidth: isWide ? 900 : double.infinity),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _buildHeader(isWide),
                    const SizedBox(height: 24),
                    GeofenceStatusCard(result: _geofenceResult, isLoading: false, onRetry: _checkGeofence),
                    const SizedBox(height: 24),
                    _buildSessionCard(), 
                    const SizedBox(height: 24),
                    Expanded(child: isWide ? _buildWebSplitLayout() : _buildMobileLayout()),
                  ],
                ),
              ),
            );
          }),
          if (_showSuccess) _buildSuccessOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isWide) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Attendance Terminal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
            Text(DateFormat('EEEE, MMM d, yyyy').format(_now), style: const TextStyle(color: Colors.white38)),
          ]),
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(DateFormat('hh:mm a').format(_now), style: const TextStyle(fontSize: 24, color: AppColors.accent, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard() {
    final clocked = _lastRecord?.isClockedIn ?? false;
    final timeIn = _lastRecord?.timeIn;
    final timeOut = _lastRecord?.timeOut;
    
    String elapsed = '--';
    if (clocked && timeIn != null) {
      try {
        final start = DateTime.parse('${_lastRecord!.date} $timeIn');
        final diff = _now.difference(start);
        elapsed = '${diff.inHours}h ${diff.inMinutes % 60}m ${diff.inSeconds % 60}s';
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: clocked ? AppColors.success.withValues(alpha: 0.3) : AppColors.cardBorder)
      ),
      child: Row(
        children: [
          _sessionInfo('TIME IN', timeIn != null ? _fmt12(timeIn) : '--:--', AppColors.success),
          _sessionInfo('TIME OUT', timeOut != null ? _fmt12(timeOut) : '--:--', AppColors.accentSecondary),
          _sessionInfo('ELAPSED', elapsed, AppColors.accent),
        ],
      ),
    );
  }

  Widget _sessionInfo(String label, String value, Color color) {
    return Expanded(
      child: Column(children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: (value == '--:--' || value == '--') ? Colors.white24 : Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _buildWebSplitLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildClockRing()),
        const SizedBox(width: 40),
        Expanded(child: Column(children: [_buildMethodSelector(), const SizedBox(height: 20), _buildMethodContent()])),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        children: [_buildClockRing(), const SizedBox(height: 32), _buildMethodSelector(), const SizedBox(height: 24), _buildMethodContent()],
      ),
    );
  }

  Widget _buildClockRing() {
    bool isClockedIn = _lastRecord?.isClockedIn ?? false;
    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) => Transform.scale(scale: _pulseAnim.value, child: child),
        child: GestureDetector(
          onTap: _handleClockTap,
          child: Container(
            width: 180, height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle, 
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.2), width: 8),
              boxShadow: [
                BoxShadow(color: AppColors.accent.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 5)
              ]
            ),
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.gradientPrimary),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_processing)
                    const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                  else ...[
                    Icon(isClockedIn ? Icons.logout_rounded : Icons.fingerprint_rounded, size: 50, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(isClockedIn ? 'CLOCK OUT' : 'CLOCK IN', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Row(
      children: _methods.asMap().entries.map((e) {
        bool active = _selectedMethod == e.key;
        return Expanded(
          child: InkWell(
            onTap: () {
              setState(() => _selectedMethod = e.key);
              if (_methods[e.key].type == AttendanceMethod.pin) {
                _scrollToBottom();
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: active ? AppColors.accent.withValues(alpha: 0.1) : AppColors.card, 
                borderRadius: BorderRadius.circular(12), 
                border: Border.all(color: active ? AppColors.accent : Colors.white10)
              ),
              child: Column(children: [Icon(e.value.icon, color: active ? AppColors.accent : Colors.white30, size: 20), const SizedBox(height: 4), Text(e.value.label, style: TextStyle(fontSize: 9, color: active ? Colors.white : Colors.white30))]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMethodContent() {
    final type = _methods[_selectedMethod].type;
    if (type == AttendanceMethod.pin) return _buildPinInput();
    return Container(
      padding: const EdgeInsets.all(24),
      child: Text(
        type == AttendanceMethod.nfc ? 'PLEASE TAP YOUR KEYFOB TO THE BACK OF THE DEVICE' : 'Authenticate using physical sensors',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildPinInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card, 
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05))
      ),
      child: Column(
        children: [
          const Text('Enter PIN to Clock In/Out', 
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.5)
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _pinController,
            obscureText: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: const TextStyle(fontSize: 24, letterSpacing: 16, color: AppColors.accent, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), letterSpacing: 16),
              filled: true,
              fillColor: Colors.black26,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.05))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
            ),
            onChanged: (val) {
              if (val.length == 4) {
                _handlePinSubmit(val);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Center(
          child: ScaleTransition(
            scale: _successAnim,
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(28), border: Border.all(color: AppColors.success.withValues(alpha: 0.5))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 60),
                  const SizedBox(height: 16),
                  Text(_successMessage, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 12),
                  Text(_successSubMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _fmt12(String t) {
    try { return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t)); } catch (_) { return t; }
  }
}

class _ClockMethod {
  final IconData icon;
  final String label;
  final Color color;
  final AttendanceMethod type;
  _ClockMethod({required this.icon, required this.label, required this.color, required this.type});
}
