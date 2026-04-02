// lib/screens/clock_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:camera/camera.dart';
import 'package:nfc_manager/nfc_manager.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/auth_service.dart';
import '../services/geofence_service.dart';
import '../widgets/geofence_indicator.dart';
import '../data/local/dao/connectivity_service.dart';
import '../data/local/dao/sync_service.dart';
import '../models/attendance.dart';
import '../models/employee.dart';

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});
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
  bool   _isOnline          = true;
  bool   _savedOffline      = false;
  String _successMessage    = '';
  String _successSubMessage = '';
  int    _selectedMethod    = 0;
  String _pinInput          = '';
  int    _pendingCount      = 0;

  GeofenceResult? _geofenceResult;
  bool _geofenceLoading = false;
  StreamSubscription<GeofenceResult>? _geofenceSub;

  StreamSubscription? _syncSub;
  StreamSubscription? _connectivitySub;
  StreamSubscription? _attendanceSub;
  late Timer  _timer;
  DateTime    _now  = DateTime.now();
  final _uuid = const Uuid();

  late final List<_ClockMethod> _methods = [
    _ClockMethod(
      icon:  Icons.contactless_rounded,
      label: 'NFC Tag',
      color: AppColors.accentSecondary,
      type:  AttendanceMethod.nfc,
    ),
    _ClockMethod(
      icon:  Icons.face_retouching_natural,
      label: 'Face ID',
      color: AppColors.accent,
      type:  AttendanceMethod.face,
    ),
    _ClockMethod(
      icon:  Icons.fingerprint_rounded,
      label: 'Fingerprint',
      color: AppColors.accentSecondary,
      type:  AttendanceMethod.fingerprint,
    ),
    _ClockMethod(
      icon:  Icons.pin_rounded,
      label: 'PIN',
      color: AppColors.warning,
      type:  AttendanceMethod.pin,
    ),
    _ClockMethod(
      icon:  Icons.qr_code_rounded,
      label: 'QR Code',
      color: AppColors.success,
      type:  AttendanceMethod.qrCode,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _successController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _successAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _successController, curve: Curves.elasticOut));

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _isOnline = ConnectivityService.instance.isOnline;
    _syncSub  = SyncService.instance.events.listen((e) {
      if (mounted) setState(() => _pendingCount = e.pendingCount);
    });
    _connectivitySub =
        ConnectivityService.instance.onStatusChange.listen((online) {
          if (mounted) setState(() => _isOnline = online);
        });
    _attendanceSub =
        DatabaseService.instance.onAttendanceChanged.listen((_) {
          if (mounted) _loadData();
        });
    _geofenceSub = GeofenceService.instance.statusStream.listen((r) {
      if (mounted) setState(() => _geofenceResult = r);
    });

    _checkGeofence();
    GeofenceService.instance.startMonitoring();
    _loadData();
    _refreshPendingCount();
    _startNfcSession();
  }

  // ── Geofence ───────────────────────────────────────────────────────────────
  Future<void> _checkGeofence() async {
    if (!mounted) return;
    setState(() => _geofenceLoading = true);
    try {
      final result = await GeofenceService.instance.checkGeofence();
      if (mounted) setState(() { _geofenceResult = result; _geofenceLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _geofenceLoading = false);
    }
  }

  Future<bool> _assertInsideGeofence() async {
    setState(() => _geofenceLoading = true);
    try {
      final result = await GeofenceService.instance.checkGeofence();
      if (mounted) setState(() { _geofenceResult = result; _geofenceLoading = false; });
      if (result.isInside) return true;
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => GeofenceBlockedDialog(
            result:    result,
            onRetry:   () => Navigator.of(context).pop(),
            onDismiss: () => Navigator.of(context).pop(),
          ),
        );
      }
      return false;
    } catch (_) {
      if (mounted) setState(() => _geofenceLoading = false);
      return false;
    }
  }

  // ── NFC ────────────────────────────────────────────────────────────────────
  Future<void> _startNfcSession() async {
    try {
      final isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) return;
      NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (NfcTag tag) async {
          if (_processing || _showSuccess) return;
          final tagId = _extractTagId(tag);
          if (tagId == null) return;
          final allowed = await _assertInsideGeofence();
          if (!allowed) return;
          if (mounted) setState(() { _processing = true; _selectedMethod = 0; });
          try {
            final employee =
            await DatabaseService.instance.getEmployeeByNfcTag(tagId);
            if (employee != null) {
              final prev  = _employee;
              _employee   = employee;
              _lastRecord = await DatabaseService.instance
                  .getTodayAttendance(employee.id);
              await _recordAttendance(AttendanceMethod.nfc, nfcTagId: tagId);
              if (mounted && prev?.id != employee.id) _employee = prev;
            } else {
              _showSnack('Unregistered NFC Tag: $tagId', AppColors.error);
              if (mounted) setState(() => _processing = false);
            }
          } catch (e) {
            _showSnack('NFC error: $e', AppColors.error);
            if (mounted) setState(() => _processing = false);
          }
        },
      );
    } catch (e) {
      debugPrint('NFC Start Error: $e');
    }
  }

  String? _extractTagId(NfcTag tag) {
    try {
      final tagMap = tag.data as Map<String, dynamic>;
      List<int>? tryKey(String k) {
        final tech = tagMap[k] as Map<dynamic, dynamic>?;
        if (tech == null) return null;
        final raw = tech['identifier'];
        if (raw is List) return raw.cast<int>();
        return null;
      }
      final id = tryKey('nfca')   ?? tryKey('nfcb')  ?? tryKey('nfcf') ??
          tryKey('nfcv')   ?? tryKey('isodep') ??
          tryKey('mifare-classic') ?? tryKey('mifare-ultralight');
      if (id == null || id.isEmpty) return null;
      return id.map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join(':').toUpperCase();
    } catch (_) { return null; }
  }

  // ── Camera / Face ID ───────────────────────────────────────────────────────
  Future<void> _openCameraScreen() async {
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (e) {
      _showSnack('Cannot access camera: $e', AppColors.error);
      return;
    }

    if (cameras.isEmpty) {
      _showSnack('No camera found on this device.', AppColors.warning);
      return;
    }

    final front = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    if (!mounted) return;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final captured = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        fullscreenDialog: true,
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, anim, __) => _CameraScreen(camera: front),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    if (captured == true && mounted) {
      await _recordAttendance(AttendanceMethod.face);
    } else {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── Data ───────────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      final empId = await SecurityService.instance.getCurrentEmployeeId();
      if (empId == null) return;
      final employee = await DatabaseService.instance.getEmployeeById(empId);
      final record   = await DatabaseService.instance.getTodayAttendance(empId);
      if (mounted) {
        setState(() {
          _employee   = employee;
          _lastRecord = record;
          _loading    = false;
        });
      }
    } catch (e) {
      debugPrint('Load data error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshPendingCount() async {
    try {
      final count = await SyncService.instance.getPendingCount();
      if (mounted) setState(() => _pendingCount = count);
    } catch (_) {}
  }

  // ── Authentication ─────────────────────────────────────────────────────────
  Future<void> _authenticate() async {
    if (_processing) return;
    final allowed = await _assertInsideGeofence();
    if (!allowed) return;

    final method = _methods[_selectedMethod];

    if (method.type == AttendanceMethod.face) {
      setState(() => _processing = true);
      await _openCameraScreen();
      return;
    }

    if (method.type == AttendanceMethod.nfc) {
      _showSnack('Please tap your NFC Keyfob/Tag near the device.',
          AppColors.accentSecondary);
      return;
    }

    setState(() => _processing = true);
    bool success = false;

    try {
      switch (method.type) {
        case AttendanceMethod.fingerprint:
          success = await SecurityService.instance
              .authenticateWithBiometric(reason: 'Verify identity');
          break;
        case AttendanceMethod.pin:
          if (_pinInput.length == 4) {
            success = await SecurityService.instance
                .verifyPin(_employee?.id ?? '', _pinInput);
            setState(() => _pinInput = '');
          } else {
            setState(() => _processing = false);
            return;
          }
          break;
        case AttendanceMethod.qrCode:
          success = true;
          break;
        default:
          break;
      }
    } catch (e) {
      _showSnack('Auth error: $e', AppColors.error);
      if (mounted) setState(() => _processing = false);
      return;
    }

    if (success) {
      await _recordAttendance(method.type);
    } else {
      _showSnack('Authentication failed.', AppColors.error);
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _authenticatePin() async {
    if (_processing) return;
    final allowed = await _assertInsideGeofence();
    if (!allowed) { setState(() => _pinInput = ''); return; }
    await _authenticate();
  }

  bool get _isClockedIn => _lastRecord?.isClockedIn ?? false;

  // ── Record Attendance ──────────────────────────────────────────────────────
  Future<void> _recordAttendance(
      AttendanceMethod method, {
        String? nfcTagId,
      }) async {
    final now     = DateTime.now();
    final today   = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);
    final employee = _employee;

    if (employee == null) {
      if (mounted) setState(() => _processing = false);
      return;
    }

    Attendance? targetRecord = _lastRecord;
    if (method == AttendanceMethod.nfc) {
      try {
        targetRecord = await DatabaseService.instance
            .getTodayAttendance(employee.id);
      } catch (_) {
        targetRecord = _lastRecord;
      }
    }

    final isClockedIn = targetRecord?.isClockedIn ?? false;

    final geoResult   = _geofenceResult;
    final gpsLat      = geoResult?.position?.latitude;
    final gpsLng      = geoResult?.position?.longitude;
    final gpsAccuracy = geoResult?.position?.accuracy;
    final gpsNotes    = gpsLat != null
        ? 'GPS: ${gpsLat.toStringAsFixed(5)},'
        '${gpsLng!.toStringAsFixed(5)} '
        '±${gpsAccuracy!.toStringAsFixed(0)}m'
        : null;

    final displayDate = DateFormat('MMM dd, yyyy').format(now);
    final displayTime = DateFormat('hh:mm:ss a').format(now);
    
    // Get Firebase UID if logged in
    final firebaseUid = AuthService.instance.currentUser?.uid;

    try {
      if (isClockedIn && targetRecord != null) {
        // 1. Update Local SQLite
        await DatabaseService.instance.updateTimeOut(targetRecord.id, timeStr);
        
        // 2. Queue for Firebase
        await SyncService.instance.enqueue(SyncType.clockOut, {
          'attendance_id':     targetRecord.id,
          'employee_id':       employee.employeeId,
          'employee_name':     employee.fullName, // ADDED NAME
          'uid':               firebaseUid,
          'date':              today,
          'time_out':          timeStr,
          'saved_at':          now.toIso8601String(),
          'nfc_tag':           nfcTagId,
          'gps_lat':           gpsLat,
          'gps_lng':           gpsLng,
          'gps_accuracy':      gpsAccuracy,
          'geofence_distance': geoResult?.distanceMeters,
        });
        
        await _loadData();
        _showSuccessOverlay(
          'Clock Out Successful',
          subMessage: '${employee.fullName}\n'
              'Date:  $displayDate\n'
              'Time:  $displayTime\n'
              'SN:    ${nfcTagId ?? "N/A"}\n'
              '${gpsNotes ?? ""}',
          savedOffline: !ConnectivityService.instance.isOnline || firebaseUid == null,
        );
      } else {
        final isLate = now.hour > 9 || (now.hour == 9 && now.minute > 0);
        final attendance = Attendance(
          id:         _uuid.v4(),
          employeeId: employee.id,
          date:       today,
          timeIn:     timeStr,
          status:     isLate ? AttendanceStatus.late : AttendanceStatus.present,
          method:     method,
          createdAt:  now,
          notes: [
            if (nfcTagId != null) 'NFC: $nfcTagId',
            if (gpsNotes != null) gpsNotes,
          ].join(' | ').nullIfEmpty,
        );
        
        // 1. Save to Local SQLite
        await DatabaseService.instance.logAttendance(attendance);
        
        // 2. Queue for Firebase
        await SyncService.instance.enqueue(SyncType.clockIn, {
          'attendance_id':     attendance.id,
          'employee_id':       employee.employeeId,
          'employee_name':     employee.fullName, // ADDED NAME
          'uid':               firebaseUid,
          'date':              today,
          'time_in':           timeStr,
          'status':            isLate ? 'late' : 'present',
          'method':            method.name,
          'saved_at':          now.toIso8601String(),
          'nfc_tag':           nfcTagId,
          'gps_lat':           gpsLat,
          'gps_lng':           gpsLng,
          'gps_accuracy':      gpsAccuracy,
          'geofence_distance': geoResult?.distanceMeters,
        });
        
        await _loadData();
        _showSuccessOverlay(
          'Clock In Successful',
          subMessage: '${employee.fullName}\n'
              'Date:  $displayDate\n'
              'Time:  $displayTime\n'
              'SN:    ${nfcTagId ?? "N/A"}\n'
              '${gpsNotes ?? ""}',
          savedOffline: !ConnectivityService.instance.isOnline || firebaseUid == null,
          isLate: isLate,
        );
      }
    } catch (e) {
      _showSnack('Record error: $e', AppColors.error);
    }

    await _refreshPendingCount();
    if (mounted) setState(() => _processing = false);
  }

  void _showSuccessOverlay(
      String message, {
        String subMessage   = '',
        bool   savedOffline = false,
        bool   isLate       = false,
      }) {
    setState(() {
      _showSuccess       = true;
      _successMessage    = message;
      _successSubMessage = subMessage;
      _savedOffline      = savedOffline;
    });
    _successController.forward(from: 0);
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) { setState(() => _showSuccess = false); _loadData(); }
    });
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
    ));
  }

  @override
  void dispose() {
    _timer.cancel();
    try { NfcManager.instance.stopSession(); } catch (_) {}
    _pulseController.dispose();
    _successController.dispose();
    _syncSub?.cancel();
    _connectivitySub?.cancel();
    _attendanceSub?.cancel();
    _geofenceSub?.cancel();
    GeofenceService.instance.stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 12),
                  _buildStatusBar(),
                  const SizedBox(height: 10),
                  GeofenceStatusCard(
                    result:    _geofenceResult,
                    isLoading: _geofenceLoading,
                    onRetry:   _checkGeofence,
                  ),
                  const SizedBox(height: 14),
                  _buildCurrentSessionCard(),
                  const SizedBox(height: 24),
                  _buildClockRing(),
                  const SizedBox(height: 24),
                  _buildMethodSelector(),
                  const SizedBox(height: 20),
                  _buildMethodContent(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          if (_showSuccess) _buildSuccessOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Attendance',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -1)),
          Text(
            DateFormat('EEEE, MMMM d · hh:mm:ss a').format(_now),
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontFamily: 'monospace'),
          ),
        ]),
      ),
      if (_pendingCount > 0)
        GestureDetector(
          onTap: _showSyncSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.warning.withOpacity(0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.cloud_upload_outlined,
                  color: AppColors.warning, size: 14),
              const SizedBox(width: 4),
              Text('$_pendingCount pending',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _isOnline
            ? AppColors.success.withOpacity(0.08)
            : AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _isOnline
                ? AppColors.success.withOpacity(0.25)
                : AppColors.warning.withOpacity(0.35)),
      ),
      child: Row(children: [
        Icon(_isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            color: _isOnline ? AppColors.success : AppColors.warning,
            size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _isOnline
                ? 'Online — synced to database'
                : 'Offline — saved to device',
            style: TextStyle(
                fontSize: 11,
                color: _isOnline ? AppColors.success : AppColors.warning,
                fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }

  Widget _buildCurrentSessionCard() {
    final clocked = _isClockedIn;
    final timeIn  = _lastRecord?.timeIn;
    final timeOut = _lastRecord?.timeOut;

    String elapsed = '--';
    if (clocked && timeIn != null) {
      try {
        final start = DateTime.parse('${_lastRecord!.date} $timeIn');
        final diff  = _now.difference(start);
        elapsed = '${diff.inHours}h ${diff.inMinutes % 60}m ${diff.inSeconds % 60}s';
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: clocked
                ? AppColors.success.withOpacity(0.3)
                : AppColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(
            clocked ? 'Active Session' : 'No Active Session',
            style: TextStyle(
                color: clocked ? AppColors.success : AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5),
          ),
          const Spacer(),
          if (clocked)
            Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TIME IN',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                timeIn != null ? _fmt12(timeIn) : '--:--',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
              if (timeIn != null) ...[
                const SizedBox(height: 2),
                Text(_lastRecord!.date,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 10)),
              ],
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const Text('TIME OUT',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                timeOut != null ? _fmt12(timeOut) : '--:--',
                style: TextStyle(
                    color: timeOut != null
                        ? AppColors.accentSecondary
                        : AppColors.textMuted,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
              if (timeOut != null) ...[
                const SizedBox(height: 2),
                Text(_lastRecord!.date,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 10)),
              ],
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('ELAPSED',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                clocked ? elapsed : '--',
                style: TextStyle(
                    color: clocked ? AppColors.accent : AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace'),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _buildClockRing() {
    final method  = _methods[_selectedMethod];
    final blocked = !(_geofenceResult?.isInside ?? false);
    final ringColor =
    blocked && !_geofenceLoading ? AppColors.error : method.color;

    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) =>
            Transform.scale(scale: _pulseAnim.value, child: child),
        child: GestureDetector(
          onTap: method.type != AttendanceMethod.qrCode ? _authenticate : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 170, height: 170,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: ringColor.withOpacity(0.3), width: 3)),
                child: Center(
                  child: Container(
                    width: 130, height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [
                        ringColor.withOpacity(0.3),
                        ringColor.withOpacity(0.1),
                      ]),
                      border: Border.all(
                          color: ringColor.withOpacity(0.5), width: 2),
                    ),
                    child: Center(
                      child: _processing
                          ? CircularProgressIndicator(
                          color: ringColor, strokeWidth: 3)
                          : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            blocked && !_geofenceLoading
                                ? Icons.location_off_rounded
                                : method.icon,
                            color: ringColor,
                            size: 44,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            blocked && !_geofenceLoading
                                ? 'Out of Zone'
                                : (_isClockedIn
                                ? 'Clock Out'
                                : 'Clock In'),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: ringColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (blocked && !_geofenceLoading && !_processing)
                Positioned(
                  bottom: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primary, width: 2)),
                    child: const Icon(Icons.lock_rounded,
                        color: Colors.white, size: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Row(
        children: List.generate(_methods.length, (i) {
          final m   = _methods[i];
          final sel = _selectedMethod == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() { _selectedMethod = i; _pinInput = ''; }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? m.color.withOpacity(0.15) : AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: sel ? m.color : AppColors.cardBorder,
                      width: sel ? 1.5 : 1),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(m.icon,
                      color: sel ? m.color : AppColors.textMuted, size: 22),
                  const SizedBox(height: 4),
                  Text(m.label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                          sel ? FontWeight.w700 : FontWeight.w400,
                          color: sel ? m.color : AppColors.textMuted)),
                ]),
              ),
            ),
          );
        }));
  }

  Widget _buildMethodContent() {
    final method = _methods[_selectedMethod];
    switch (method.type) {
      case AttendanceMethod.nfc:       return _buildNfcPrompt();
      case AttendanceMethod.pin:       return _buildPinInput();
      case AttendanceMethod.qrCode:    return _buildQRCode();
      default:                         return _buildBioPrompt();
    }
  }

  Widget _buildNfcPrompt() {
    final c = _methods.first.color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: c.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withOpacity(0.2))),
      child: Row(children: [
        Icon(Icons.contactless_rounded, color: c, size: 18),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'NFC is Active. Tap your Keyfob or ID Card to '
                'record attendance automatically.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12, height: 1.5),
          ),
        ),
      ]),
    );
  }

  Widget _buildBioPrompt() {
    final method = _methods[_selectedMethod];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: method.color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: method.color.withOpacity(0.2))),
      child: Row(children: [
        Icon(Icons.touch_app_outlined, color: method.color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Tap the circle to '
                '${_isClockedIn ? "clock out" : "clock in"} '
                'with ${method.label}.',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12, height: 1.5),
          ),
        ),
      ]),
    );
  }

  Widget _buildPinInput() {
    return SingleChildScrollView(
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            width: 16, height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _pinInput.length
                  ? AppColors.warning : Colors.transparent,
              border: Border.all(
                  color: i < _pinInput.length
                      ? AppColors.warning : AppColors.textMuted,
                  width: 2),
            ),
          )),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2.2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8),
          itemCount: 12,
          itemBuilder: (_, idx) {
            const rows = [
              ['1','2','3'], ['4','5','6'],
              ['7','8','9'], ['','0','del']
            ];
            final key = rows[idx ~/ 3][idx % 3];
            if (key.isEmpty) return const SizedBox();
            return GestureDetector(
              onTap: () {
                if (key == 'del') {
                  if (_pinInput.isNotEmpty) {
                    setState(() => _pinInput =
                        _pinInput.substring(0, _pinInput.length - 1));
                  }
                } else if (_pinInput.length < 4) {
                  setState(() => _pinInput += key);
                  if (_pinInput.length == 4) {
                    Future.delayed(const Duration(milliseconds: 250),
                        _authenticatePin);
                  }
                }
              },
              child: Container(
                decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder)),
                child: Center(
                  child: key == 'del'
                      ? const Icon(Icons.backspace_outlined,
                      color: AppColors.textSecondary, size: 20)
                      : Text(key,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
              ),
            );
          },
        ),
      ]),
    );
  }

  Widget _buildQRCode() {
    final token = SecurityService.instance.generateAttendanceToken(
        _employee?.employeeId ?? 'EMP',
        DateFormat('yyyy-MM-dd').format(DateTime.now()));
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          QrImageView(
              data: '${_employee?.employeeId}:$token',
              version: QrVersions.auto,
              size: 170,
              backgroundColor: Colors.white),
          const SizedBox(height: 8),
          const Text('Show to HR officer',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    final color = _savedOffline ? AppColors.warning : AppColors.success;
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Center(
          child: ScaleTransition(
            scale: _successAnim,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: color.withOpacity(0.5), width: 2),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 10),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: Icon(
                      _savedOffline
                          ? Icons.cloud_off_rounded
                          : Icons.check_circle_rounded,
                      color: color, size: 44),
                ),
                const SizedBox(height: 16),
                Text(
                  _successMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    _successSubMessage,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.7,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                if (_savedOffline) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.warning.withOpacity(0.3)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.cloud_off_rounded,
                          color: AppColors.warning, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Saved offline — will sync when online',
                        style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => setState(() => _showSuccess = false),
                  child: const Text('DISMISS',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          fontSize: 13)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _showSyncSheet() {
    showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.card,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => const _SyncQueueSheet());
  }

  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try {
      return DateFormat('hh:mm a')
          .format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) { return t; }
  }
}

// ─── Camera Screen ────────────────────────────────────────────────────────────
class _CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const _CameraScreen({required this.camera});

  @override
  State<_CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<_CameraScreen> {
  CameraController? _ctrl;
  bool _ready      = false;
  bool _capturing  = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    final ctrl = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await ctrl.initialize();
      if (mounted) {
        setState(() { _ctrl = ctrl; _ready = true; });
      } else {
        await ctrl.dispose();
      }
    } catch (e) {
      await ctrl.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera failed: $e'),
              backgroundColor: AppColors.error),
        );
        Navigator.of(context).pop(false);
      }
    }
  }

  Future<void> _capture() async {
    if (_capturing || _ctrl == null || !_ready) return;
    setState(() => _capturing = true);
    try {
      await _ctrl!.takePicture();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _capturing = false);
      }
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: !_ready || _ctrl == null
          ? const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: AppColors.accent),
          SizedBox(height: 16),
          Text('Starting camera…',
              style: TextStyle(color: Colors.white70)),
        ]),
      )
          : Stack(fit: StackFit.expand, children: [
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _ctrl!.value.previewSize!.height,
                height: _ctrl!.value.previewSize!.width,
                child: CameraPreview(_ctrl!),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            height: 160,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
          ),
        ),
        const Positioned(
          top: 60, left: 0, right: 0,
          child: Column(children: [
            Icon(Icons.face_retouching_natural,
                color: AppColors.accent, size: 32),
            SizedBox(height: 8),
            Text('Face Recognition',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Position your face inside the frame',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white60, fontSize: 13)),
          ]),
        ),
        Center(
          child: Container(
            width: 240, height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(120),
              border: Border.all(
                  color: AppColors.accent.withOpacity(0.8),
                  width: 2.5),
            ),
          ),
        ),
        Center(
          child: SizedBox(
            width: 240, height: 300,
            child: CustomPaint(painter: _CornerPainter()),
          ),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 50, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(false),
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 26),
                ),
              ),
              GestureDetector(
                onTap: _capturing ? null : _capture,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      AppColors.accent,
                      AppColors.accentSecondary,
                    ]),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: _capturing
                      ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.camera_alt_rounded,
                      color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(width: 56, height: 56),
            ],
          ),
        ),
      ]),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 28.0;
    const r   = 20.0;

    canvas.drawLine(Offset(r, 0),            Offset(r + len, 0),          paint);
    canvas.drawLine(Offset(0, r),            Offset(0, r + len),          paint);
    canvas.drawLine(Offset(size.width-r-len,0), Offset(size.width-r,0),   paint);
    canvas.drawLine(Offset(size.width,r),    Offset(size.width,r+len),    paint);
    canvas.drawLine(Offset(0,size.height-r-len), Offset(0,size.height-r), paint);
    canvas.drawLine(Offset(r,size.height),   Offset(r+len,size.height),   paint);
    canvas.drawLine(Offset(size.width-r-len,size.height),
        Offset(size.width-r,size.height), paint);
    canvas.drawLine(Offset(size.width,size.height-r-len),
        Offset(size.width,size.height-r), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _SyncQueueSheet extends StatefulWidget {
  const _SyncQueueSheet();
  @override State<_SyncQueueSheet> createState() => _SyncQueueSheetState();
}

class _SyncQueueSheetState extends State<_SyncQueueSheet> {
  List<SyncRecord> _records = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final records = await SyncService.instance.getRecentQueue();
    if (mounted) setState(() { _records = records; _loading = false; });
  }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Sync Queue',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const Spacer(),
            if (!ConnectivityService.instance.isOnline)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('OFFLINE',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w800)),
              )
            else
              TextButton.icon(
                onPressed: () async {
                  await SyncService.instance.syncPending();
                  await _load();
                },
                icon: const Icon(Icons.sync_rounded,
                    size: 16, color: AppColors.accent),
                label: const Text('Sync Now',
                    style: TextStyle(fontSize: 12, color: AppColors.accent)),
              ),
          ]),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(color: AppColors.accent))
          else if (_records.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('All records synced ✓',
                    style: TextStyle(
                        color: AppColors.success, fontSize: 14)),
              ),
            )
          else
            ...(_records.take(8).map((r) => _buildRow(r))),
        ],
      ),
    );
  }
  Widget _buildRow(SyncRecord r) {
    final statusColor = {
      SyncStatus.pending: AppColors.warning,
      SyncStatus.syncing: AppColors.accentSecondary,
      SyncStatus.synced:  AppColors.success,
      SyncStatus.failed:  AppColors.error,
    }[r.status] ??
        AppColors.textMuted;
    final icon = r.type == SyncType.clockIn
        ? Icons.login_rounded : Icons.logout_rounded;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder)),
      child: Row(children: [
        Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                shape: BoxShape.circle),
            child: Icon(icon, color: statusColor, size: 18)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.type == SyncType.clockIn ? 'Clock In' : 'Clock Out',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            Text(r.createdAt.toString().substring(0, 16),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Text(r.status.name.toUpperCase(),
              style: TextStyle(
                  fontSize: 9,
                  color: statusColor,
                  fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class _ClockMethod {
  final IconData         icon;
  final String           label;
  final Color            color;
  final AttendanceMethod type;
  const _ClockMethod({
    required this.icon,
    required this.label,
    required this.color,
    required this.type,
  });
}

extension _StringNullIfEmpty on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
