// lib/screens/landing_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'login_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Geofence config
// ═══════════════════════════════════════════════════════════════════════════
const double _kOfficeLat     = 14.602120;                           // office latitude
const double _kOfficeLng     = 120.999292;                          // office longitude
const double _kRadiusMeters  = 100.0;                               // allowed radius in metres
const String _kOfficeAddress = '240 Lacson Ave, Sampaloc, Manila';  // display address

// ── Lightweight result model ──────────────────────────────────────────────
class _GeoResult {
  final bool isInside;
  final double? distanceMeters;
  final String? error;
  const _GeoResult({required this.isInside, this.distanceMeters, this.error});
}

// ── Standalone geofence helper (no singleton dependency needed here) ──────
Future<_GeoResult> _checkLandingGeo() async {
  try {
    // 1. Service enabled?
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const _GeoResult(isInside: false, error: 'Location services disabled');
    }

    // 2. Permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return const _GeoResult(isInside: false, error: 'Location permission denied');
    }

    // 3. Position
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );

    // 4. Distance
    final dist = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      _kOfficeLat, _kOfficeLng,
    );

    return _GeoResult(isInside: dist <= _kRadiusMeters, distanceMeters: dist);
  } catch (e) {
    return _GeoResult(isInside: false, error: e.toString());
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LandingScreen
// ═══════════════════════════════════════════════════════════════════════════
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {

  // ── Animation controllers ────────────────────────────────────────────────
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _rotateController;
  late AnimationController _pulseController;
  late AnimationController _featureSlideController;
  late AnimationController _glowController;
  late AnimationController _radarController;
  late AnimationController _pinBounceController;
  late AnimationController _rippleController;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _rotateAnim;
  late Animation<double> _pulseAnim;
  late Animation<Offset> _featureSlideAnim;
  late Animation<double> _featureFadeAnim;
  late Animation<double> _glowAnim;
  late Animation<double> _radarAnim;
  late Animation<double> _pinBounceAnim;
  late Animation<double> _rippleAnim;

  // ── UI state ─────────────────────────────────────────────────────────────
  int   _currentFeature = 0;
  Timer? _featureTimer;
  bool  _menuOpen = false;

  // Geo-fence visual state — driven by real GPS result (NOT a demo timer)
  bool  _outsideRadius = false;

  // ── Real geolocation state ───────────────────────────────────────────────
  _GeoResult? _geoResult;
  bool        _geoChecking = true;   // true while the first check is running

  // ── Design tokens ────────────────────────────────────────────────────────
  static const Color _blackDeep  = Color(0xFF040404);
  static const Color _blackCard  = Color(0xFF0D0D0D);
  static const Color _blackLight = Color(0xFF141414);
  static const Color _orange     = Color(0xFFFF5500);
  static const Color _orangeHot  = Color(0xFFFF7A1A);
  static const Color _orangeGlow = Color(0xFFFF3D00);
  static const Color _amber      = Color(0xFFFFAA00);
  static const Color _white      = Color(0xFFFFFFFF);
  static const Color _white80    = Color(0xCCFFFFFF);
  static const Color _white50    = Color(0x80FFFFFF);
  static const Color _white20    = Color(0x33FFFFFF);
  static const Color _white10    = Color(0x1AFFFFFF);
  static const Color _deny       = Color(0xFFFF2244);

  final List<_FeatureItem> _features = const [
    _FeatureItem(
      icon: Icons.face_retouching_natural_outlined,
      label: 'Face Recognition',
      detail: 'AI-powered facial biometrics with 99.7% accuracy',
      color: Color(0xFFFF5500),
      gradient: [Color(0xFFFF5500), Color(0xFFCC2200)],
    ),
    _FeatureItem(
      icon: Icons.my_location_rounded,
      label: 'Geo-Fencing',
      detail: 'Precision GPS clock-in within defined site boundaries',
      color: Color(0xFFFFAA00),
      gradient: [Color(0xFFFFAA00), Color(0xFFCC6600)],
    ),
    _FeatureItem(
      icon: Icons.fingerprint_rounded,
      label: 'Fingerprint Auth',
      detail: 'Hardware-level biometric security on every device',
      color: Color(0xFFFF7A1A),
      gradient: [Color(0xFFFF7A1A), Color(0xFFCC3300)],
    ),
    _FeatureItem(
      icon: Icons.cloud_sync_rounded,
      label: 'Real-Time Sync',
      detail: 'Instant cross-platform attendance data sync',
      color: Color(0xFFFF3D00),
      gradient: [Color(0xFFFF3D00), Color(0xFF991A00)],
    ),
  ];

  final List<_Stat> _stats = const [
    _Stat(value: '99.7%', label: 'Face Match Accuracy'),
    _Stat(value: '<0.3s',  label: 'Auth Speed'),
    _Stat(value: '500K+', label: 'Daily Check-ins'),
    _Stat(value: '99.9%', label: 'Uptime SLA'),
  ];

  // ── initState ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _fadeController         = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _slideController        = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _rotateController       = AnimationController(vsync: this, duration: const Duration(seconds: 22));
    _pulseController        = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _featureSlideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _glowController         = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _radarController        = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _pinBounceController    = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _rippleController       = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

    _fadeAnim         = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _slideAnim        = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _rotateAnim       = Tween<double>(begin: 0, end: 2 * math.pi).animate(CurvedAnimation(parent: _rotateController, curve: Curves.linear));
    _pulseAnim        = Tween<double>(begin: 0.96, end: 1.04).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _featureSlideAnim = Tween<Offset>(begin: const Offset(0.25, 0), end: Offset.zero).animate(CurvedAnimation(parent: _featureSlideController, curve: Curves.easeOutCubic));
    _featureFadeAnim  = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _featureSlideController, curve: Curves.easeOut));
    _glowAnim         = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
    _radarAnim        = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _radarController, curve: Curves.linear));
    _pinBounceAnim    = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _pinBounceController, curve: Curves.elasticOut));
    _rippleAnim       = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _rippleController, curve: Curves.easeOut));

    _fadeController.forward();
    _slideController.forward();
    _rotateController.repeat();
    _pulseController.repeat(reverse: true);
    _featureSlideController.forward();
    _glowController.repeat(reverse: true);
    _radarController.repeat();
    _rippleController.repeat();
    _pinBounceController.forward();

    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ));
    }

    _featureTimer = Timer.periodic(const Duration(seconds: 4), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _currentFeature = (_currentFeature + 1) % _features.length);
      _featureSlideController.forward(from: 0);
    });

    // Real GPS check on mount
    _runGeoCheck();
  }

  // ── Real geolocation check ───────────────────────────────────────────────
  Future<void> _runGeoCheck() async {
    if (mounted) setState(() => _geoChecking = true);
    final result = await _checkLandingGeo();
    if (mounted) setState(() {
      _geoResult     = result;
      _geoChecking   = false;
      _outsideRadius = !(result.isInside); // sync visual widget to real GPS
    });
  }

  // ── Navigation guard ─────────────────────────────────────────────────────
  void _onGetStarted() {
    if (_geoChecking) {
      _showGeoSnack('Verifying your location…', _orange, retry: false);
      return;
    }
    if (!(_geoResult?.isInside ?? false)) {
      final dist = _geoResult?.distanceMeters;
      final distStr = dist != null ? '${dist.toStringAsFixed(0)} m away' : 'unknown distance';
      final errStr  = _geoResult?.error;
      _showGeoSnack(
        errStr != null
            ? 'Location error: $errStr'
            : 'You are $distStr from $_kOfficeAddress. Move inside the zone to continue.',
        _deny,
        retry: true,
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _onSignIn() {
    // Sign-in page is always accessible (employee may be logging in remotely
    // for admin tasks). Remove this guard if you want sign-in gated too.
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _showGeoSnack(String msg, Color color, {required bool retry}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          color == _deny ? Icons.location_off_rounded : Icons.location_searching_rounded,
          color: _white, size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(msg,
            style: const TextStyle(color: _white, fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
      backgroundColor: color == _deny ? _deny : const Color(0xFF856404),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 5),
      action: retry
          ? SnackBarAction(label: 'RETRY', textColor: _white, onPressed: _runGeoCheck)
          : null,
    ));
  }

  // ── dispose ───────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _rotateController.dispose();
    _pulseController.dispose();
    _featureSlideController.dispose();
    _glowController.dispose();
    _radarController.dispose();
    _pinBounceController.dispose();
    _rippleController.dispose();
    _featureTimer?.cancel();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 860;

    return Scaffold(
      backgroundColor: _blackDeep,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(children: [
          Positioned.fill(
            child: _CinematicBackground(rotateAnim: _rotateAnim, glowAnim: _glowAnim),
          ),
          SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              child: Column(children: [
                _buildNavbar(isMobile),
                isMobile ? _buildMobileHero() : _buildWebHero(),
                _buildStatsRow(isMobile),
                _buildFeaturesSection(isMobile),
                _buildCTASection(isMobile),
                _buildFooter(isMobile),
              ]),
            ),
          ),
          if (_menuOpen && isMobile) _buildMobileMenu(),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GEOFENCE STATUS BANNER  (shows below navbar when blocked / checking)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildGeoBanner() {
    if (_geoChecking) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        color: const Color(0xFF1A1200),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(color: _amber, strokeWidth: 2)),
          const SizedBox(width: 8),
          const Icon(Icons.location_searching_rounded, color: _amber, size: 13),
          const SizedBox(width: 6),
          const Flexible(child: Text(
            'Verifying location ·  $_kOfficeAddress',
            style: TextStyle(color: _amber, fontSize: 12,
                fontWeight: FontWeight.w600, letterSpacing: 0.3),
          )),
        ]),
      );
    }

    // Inside zone — show subtle green bar with address + distance
    if (_geoResult != null && _geoResult!.isInside) {
      final dist = _geoResult!.distanceMeters;
      final distStr = dist != null ? '  ·  ${dist.toStringAsFixed(0)} m from office' : '';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        color: const Color(0xFF071A07),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.location_on_rounded, color: Color(0xFF4CAF50), size: 13),
          const SizedBox(width: 6),
          Flexible(child: Text(
            'Inside work zone  ·  $_kOfficeAddress$distStr',
            style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 12,
                fontWeight: FontWeight.w600, letterSpacing: 0.3),
          )),
        ]),
      );
    }

    if (_geoResult == null) return const SizedBox.shrink();

    // Outside zone
    final dist = _geoResult!.distanceMeters;
    final msg = _geoResult!.error != null
        ? 'Location error — ${_geoResult!.error}'
        : dist != null
        ? 'You are ${dist.toStringAsFixed(0)} m from $_kOfficeAddress'
        : 'Outside work zone · $_kOfficeAddress';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: _deny.withOpacity(0.12),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.location_off_rounded, color: _deny, size: 14),
        const SizedBox(width: 8),
        Flexible(child: Text(msg,
            style: const TextStyle(color: _deny, fontSize: 12,
                fontWeight: FontWeight.w600, letterSpacing: 0.3))),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _runGeoCheck,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: _deny.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('RETRY',
                style: TextStyle(color: _deny, fontSize: 10,
                    fontWeight: FontWeight.w900, letterSpacing: 1)),
          ),
        ),
      ]),
    );
  }

  // ── NAVBAR ─────────────────────────────────────────────────────────────────
  Widget _buildNavbar(bool isMobile) {
    return Column(children: [
      Container(
        height: 70,
        decoration: BoxDecoration(
          color: _blackDeep.withOpacity(0.94),
          border: Border(bottom: BorderSide(color: _orange.withOpacity(0.2), width: 1)),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                _LogoMark(),
                const SizedBox(width: 14),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HRIS',
                        style: TextStyle(color: _white, fontWeight: FontWeight.w900,
                            fontSize: 15, letterSpacing: 3)),
                    Text('BIOMETRICS',
                        style: TextStyle(color: _orange, fontWeight: FontWeight.w800,
                            fontSize: 8, letterSpacing: 4)),
                  ],
                ),
                const Spacer(),
                if (!isMobile) ...[
                  _NavLink(label: 'Features', onTap: () {}),
                  _NavLink(label: 'Pricing',  onTap: () {}),
                  _NavLink(label: 'Docs',     onTap: () {}),
                  const SizedBox(width: 20),
                  _PrimaryButton(label: 'Sign In', onPressed: _onSignIn, compact: true),
                ] else
                  GestureDetector(
                    onTap: () => setState(() => _menuOpen = !_menuOpen),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: _white20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(_menuOpen ? Icons.close : Icons.menu,
                          color: _white, size: 20),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
      _buildGeoBanner(),
    ]);
  }

  // ── MOBILE MENU ───────────────────────────────────────────────────────────
  Widget _buildMobileMenu() {
    return Positioned(
      top: 70, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: _blackCard,
          border: Border(
            bottom: BorderSide(color: _orange.withOpacity(0.3), width: 1),
            left:   BorderSide(color: _orange.withOpacity(0.15), width: 1),
            right:  BorderSide(color: _orange.withOpacity(0.15), width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _MobileMenuLink(label: 'Features', onTap: () => setState(() => _menuOpen = false)),
          _MobileMenuLink(label: 'Pricing',  onTap: () => setState(() => _menuOpen = false)),
          _MobileMenuLink(label: 'Docs',     onTap: () => setState(() => _menuOpen = false)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: _GeofenceGatedButton(
              label: 'Get Started Free',
              onPressed: _onGetStarted,
              isAllowed: _geoResult?.isInside ?? false,
              isChecking: _geoChecking,
            ),
          ),
        ]),
      ),
    );
  }

  // ── WEB HERO ──────────────────────────────────────────────────────────────
  Widget _buildWebHero() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 90),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChipLabel(label: 'Enterprise Attendance Platform'),
                    const SizedBox(height: 32),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(fontSize: 60, fontWeight: FontWeight.w900,
                            color: _white, height: 1.05, letterSpacing: -2),
                        children: [
                          TextSpan(text: 'NEXT-GEN\n'),
                          TextSpan(text: 'BIOMETRIC\n',
                              style: TextStyle(color: _orange,
                                  shadows: [Shadow(color: Color(0xFFFF5500), blurRadius: 30),
                                    Shadow(color: Color(0xFFFF5500), blurRadius: 60)])),
                          TextSpan(text: 'ATTENDANCE'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(children: [
                      Container(width: 40, height: 2, color: _orange),
                      const SizedBox(width: 14),
                      Expanded(child: Text(
                        'Clock-in is locked outside the zone. Geo-fencing enforces location at the hardware level — no workarounds.',
                        style: TextStyle(fontSize: 15, color: _white80,
                            height: 1.75, fontWeight: FontWeight.w300, letterSpacing: 0.2),
                      )),
                    ]),
                    const SizedBox(height: 44),
                    // ── Gated CTA ──────────────────────────────────────────
                    Row(children: [
                      _GeofenceGatedButton(
                        label: 'Get Started Free',
                        onPressed: _onGetStarted,
                        isAllowed: _geoResult?.isInside ?? false,
                        isChecking: _geoChecking,
                      ),
                      const SizedBox(width: 16),
                      _GhostButton(label: 'Learn More', onPressed: () {}),
                    ]),
                    const SizedBox(height: 64),
                    _buildFeatureCarousel(isMobile: false),
                  ],
                ),
              ),
              const SizedBox(width: 56),
              Expanded(flex: 48, child: _buildGeoFenceWidget()),
            ],
          ),
        ),
      ),
    );
  }

  // ── MOBILE HERO ───────────────────────────────────────────────────────────
  Widget _buildMobileHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 52),
      child: Column(children: [
        _ChipLabel(label: 'Enterprise Attendance Platform'),
        const SizedBox(height: 32),
        _buildGeoFenceWidget(),
        const SizedBox(height: 40),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900,
                color: _white, height: 1.1, letterSpacing: -1.5),
            children: [
              TextSpan(text: 'NEXT-GEN '),
              TextSpan(text: 'BIOMETRIC\n',
                  style: TextStyle(color: _orange,
                      shadows: [Shadow(color: Color(0xFFFF5500), blurRadius: 20)])),
              TextSpan(text: 'ATTENDANCE'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('Clock-in is locked outside the zone. Geo-fencing enforces location at the hardware level.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _white80, height: 1.7, fontWeight: FontWeight.w300)),
        const SizedBox(height: 36),
        SizedBox(
          width: double.infinity,
          child: _GeofenceGatedButton(
            label: 'Get Started Free',
            onPressed: _onGetStarted,
            isAllowed: _geoResult?.isInside ?? false,
            isChecking: _geoChecking,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: _GhostButton(label: 'Learn More', onPressed: () {})),
        const SizedBox(height: 44),
        _buildFeatureCarousel(isMobile: true),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GEO-FENCE VISUAL WIDGET  (driven by real GPS — _outsideRadius)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildGeoFenceWidget() {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _rotateAnim, _pulseAnim, _glowAnim, _radarAnim, _pinBounceAnim, _rippleAnim,
        ]),
        builder: (context, _) {
          final activeColor = _outsideRadius ? _deny : _orange;
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _blackCard,
              border: Border.all(color: activeColor.withOpacity(0.3), width: 1.5),
              boxShadow: [BoxShadow(
                color: activeColor.withOpacity(0.18 * _glowAnim.value),
                blurRadius: 60, spreadRadius: 10,
              )],
            ),
            child: ClipOval(
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(
                  painter: _GeoFencePainter(
                    rotateAngle: _rotateAnim.value,
                    pulse: _pulseAnim.value,
                    glow: _glowAnim.value,
                    radar: _radarAnim.value,
                    ripple: _rippleAnim.value,
                    outsideRadius: _outsideRadius,
                  ),
                )),

                // Status badge — top
                Positioned(
                  top: 22, left: 0, right: 0,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(anim),
                            child: child,
                          )),
                      child: _outsideRadius
                          ? _StatusBadge(key: const ValueKey('out'), label: 'OUTSIDE ZONE', icon: Icons.gps_off_rounded, color: _deny)
                          : _StatusBadge(key: const ValueKey('in'),  label: 'INSIDE ZONE',  icon: Icons.gps_fixed_rounded, color: _orange),
                    ),
                  ),
                ),

                // HQ center marker
                Center(
                  child: Transform.scale(
                    scale: _pulseAnim.value,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF5500), Color(0xFFCC2200)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: _orange.withOpacity(0.5 * _glowAnim.value), blurRadius: 28, spreadRadius: 4)],
                        ),
                        child: const Icon(Icons.business_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _blackDeep.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _orange.withOpacity(0.4)),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('HQ OFFICE',
                              style: TextStyle(color: _orange, fontSize: 8,
                                  fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                          const SizedBox(height: 2),
                          const Text(_kOfficeAddress,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFFFF8844), fontSize: 7,
                                  fontWeight: FontWeight.w500, letterSpacing: 0.3)),
                        ]),
                      ),
                    ]),
                  ),
                ),

                _buildEmployeePin(),

                // Clock-in status — bottom
                Positioned(
                  bottom: 22, left: 0, right: 0,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                      child: _outsideRadius
                          ? _ClockInDenied(key: const ValueKey('denied'))
                          : _ClockInAllowed(key: const ValueKey('allowed')),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmployeePin() {
    const insideOffset  = Offset(0.17, -0.13);
    const outsideOffset = Offset(0.34, 0.1);
    final color  = _outsideRadius ? _deny : _orange;
    final bounce = math.sin(_pinBounceAnim.value * math.pi) * 0.04;
    final target = _outsideRadius ? outsideOffset : insideOffset;
    final offset = Offset(target.dx, target.dy - bounce);

    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: Alignment(offset.dx * 2, offset.dy * 2),
        widthFactor: 0.22, heightFactor: 0.22,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          child: Column(
            key: ValueKey(_outsideRadius),
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.7), width: 2),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.45), blurRadius: 14)],
                ),
                child: Icon(Icons.person_rounded, color: color, size: 18),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: _blackDeep.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: color.withOpacity(0.35)),
                ),
                child: Text('EMP-001',
                    style: TextStyle(color: color, fontSize: 7,
                        fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── FEATURE CAROUSEL ───────────────────────────────────────────────────────
  Widget _buildFeatureCarousel({required bool isMobile}) {
    final feature = _features[_currentFeature];
    return Column(
      crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: isMobile ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: List.generate(_features.length, (i) {
            final active = i == _currentFeature;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 6),
              width: active ? 28 : 6, height: 3,
              decoration: BoxDecoration(
                color: active ? _orange : _white20,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: _featureSlideController,
          builder: (_, __) => FadeTransition(
            opacity: _featureFadeAnim,
            child: SlideTransition(
              position: _featureSlideAnim,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _blackCard,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: feature.color.withOpacity(0.35), width: 1),
                  boxShadow: [BoxShadow(color: feature.color.withOpacity(0.08), blurRadius: 20, spreadRadius: 2)],
                ),
                child: Row(children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: feature.gradient,
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(feature.icon, color: _white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(feature.label,
                          style: const TextStyle(color: _white, fontSize: 14,
                              fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(feature.detail,
                          style: TextStyle(color: _white50, fontSize: 12, height: 1.45)),
                    ],
                  )),
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      border: Border.all(color: _white10),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, color: _white50, size: 14),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── STATS ROW ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: _blackCard,
        border: Border.symmetric(horizontal: BorderSide(color: _orange.withOpacity(0.15), width: 1)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 48, vertical: 28),
            child: isMobile
                ? Column(children: [
              Row(children: [
                Expanded(child: _StatCard(stat: _stats[0])),
                _StatDivider(),
                Expanded(child: _StatCard(stat: _stats[1])),
              ]),
              Divider(color: _white10, height: 1),
              Row(children: [
                Expanded(child: _StatCard(stat: _stats[2])),
                _StatDivider(),
                Expanded(child: _StatCard(stat: _stats[3])),
              ]),
            ])
                : Row(
              children: _stats.asMap().entries.map((e) {
                return Expanded(child: Row(children: [
                  Expanded(child: _StatCard(stat: e.value)),
                  if (e.key < _stats.length - 1) _StatDivider(),
                ]));
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── FEATURES SECTION ──────────────────────────────────────────────────────
  Widget _buildFeaturesSection(bool isMobile) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: 80),
          child: Column(children: [
            _ChipLabel(label: 'Platform Features'),
            const SizedBox(height: 20),
            Text('BUILT FOR\nENTERPRISE SCALE',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: isMobile ? 30 : 40, fontWeight: FontWeight.w900,
                    color: _white, letterSpacing: -1, height: 1.1)),
            const SizedBox(height: 8),
            Text('Everything you need for modern attendance control',
                textAlign: TextAlign.center,
                style: TextStyle(color: _white50, fontSize: 14)),
            const SizedBox(height: 52),
            isMobile
                ? Column(children: _features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _FeatureCard(feature: f))).toList())
                : GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 2.5,
              ),
              itemCount: _features.length,
              itemBuilder: (_, i) => _FeatureCard(feature: _features[i]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── CTA SECTION ───────────────────────────────────────────────────────────
  Widget _buildCTASection(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _glowAnim,
                builder: (_, __) => Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: RadialGradient(
                      center: Alignment.center, radius: 1.2,
                      colors: [_orange.withOpacity(0.1 * _glowAnim.value), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.all(isMobile ? 40 : 64),
              decoration: BoxDecoration(
                color: _blackCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _orange.withOpacity(0.3), width: 1),
                boxShadow: [BoxShadow(color: _orange.withOpacity(0.1), blurRadius: 60, spreadRadius: 4)],
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _orange.withOpacity(0.4)),
                  ),
                  child: const Text('READY TO DEPLOY',
                      style: TextStyle(color: _orange, fontSize: 10,
                          fontWeight: FontWeight.w800, letterSpacing: 3)),
                ),
                const SizedBox(height: 24),
                Text('START SECURING\nATTENDANCE TODAY',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: isMobile ? 28 : 42, fontWeight: FontWeight.w900,
                        color: _white, letterSpacing: -1, height: 1.1)),
                const SizedBox(height: 16),
                Text('Deploy in minutes. No hardware required. Works on any device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _white50, fontSize: 14, height: 1.6)),
                const SizedBox(height: 36),

                // ── Gated CTA in CTA section ─────────────────────────────
                isMobile
                    ? Column(children: [
                  SizedBox(width: double.infinity,
                    child: _GeofenceGatedButton(
                      label: 'Get Started Free',
                      onPressed: _onGetStarted,
                      isAllowed: _geoResult?.isInside ?? false,
                      isChecking: _geoChecking,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity,
                      child: _GhostButton(label: 'Contact Sales', onPressed: () {})),
                ])
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _GeofenceGatedButton(
                    label: 'Get Started Free',
                    onPressed: _onGetStarted,
                    isAllowed: _geoResult?.isInside ?? false,
                    isChecking: _geoChecking,
                  ),
                  const SizedBox(width: 16),
                  _GhostButton(label: 'Contact Sales', onPressed: () {}),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── FOOTER ────────────────────────────────────────────────────────────────
  Widget _buildFooter(bool isMobile) {
    return Container(
      margin: const EdgeInsets.only(top: 64),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: 32),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _white10, width: 1))),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: isMobile
              ? Column(children: [
            _LogoMark(),
            const SizedBox(height: 16),
            Text('© 2025 HRIS Biometrics. All rights reserved.',
                style: TextStyle(color: _white20, fontSize: 11, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Text('v2.0 · Cross-Platform Ready',
                style: TextStyle(color: _white20, fontSize: 10, letterSpacing: 1)),
          ])
              : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              _LogoMark(),
              const SizedBox(width: 14),
              Text('HRIS BIOMETRICS',
                  style: TextStyle(color: _white50, fontWeight: FontWeight.w800,
                      letterSpacing: 2, fontSize: 12)),
            ]),
            Text('© 2025 HRIS Biometrics. All rights reserved.',
                style: TextStyle(color: _white20, fontSize: 11)),
            Text('v2.0 · Cross-Platform Ready',
                style: TextStyle(color: _white20, fontSize: 11, letterSpacing: 0.5)),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GEOFENCE-GATED BUTTON
// ════════════════════════════════════════════════════════════════════════════
class _GeofenceGatedButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isAllowed;
  final bool isChecking;
  const _GeofenceGatedButton({
    required this.label,
    required this.onPressed,
    required this.isAllowed,
    required this.isChecking,
  });

  @override
  State<_GeofenceGatedButton> createState() => _GeofenceGatedButtonState();
}

class _GeofenceGatedButtonState extends State<_GeofenceGatedButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final blocked      = !widget.isAllowed && !widget.isChecking;
    final checking     = widget.isChecking;
    final activeGrad   = _hovered && !blocked && !checking
        ? [const Color(0xFFFF7A1A), const Color(0xFFFF3D00)]
        : blocked
        ? [const Color(0xFF3A3A3A), const Color(0xFF222222)]
        : checking
        ? [const Color(0xFF4A3A00), const Color(0xFF2A2200)]
        : [const Color(0xFFFF5500), const Color(0xFFCC2200)];

    return MouseRegion(
      cursor: (blocked || checking)
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: activeGrad,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(4),
            border: blocked
                ? Border.all(color: const Color(0xFF555555), width: 1)
                : checking
                ? Border.all(color: const Color(0xFFFFAA00).withOpacity(0.4), width: 1)
                : null,
            boxShadow: (!blocked && !checking)
                ? [BoxShadow(
                color: const Color(0xFFFF5500).withOpacity(_hovered ? 0.5 : 0.25),
                blurRadius: _hovered ? 24 : 12,
                offset: Offset(0, _hovered ? 6 : 4))]
                : null,
          ),
          child: checking
              ? const Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(color: Color(0xFFFFAA00), strokeWidth: 2)),
            SizedBox(width: 10),
            Text('CHECKING LOCATION…',
                style: TextStyle(color: Color(0xFFFFAA00), fontWeight: FontWeight.w800,
                    fontSize: 12, letterSpacing: 1.2)),
          ])
              : Row(mainAxisSize: MainAxisSize.min, children: [
            if (blocked) ...[
              const Icon(Icons.location_off_rounded, color: Color(0xFF888888), size: 15),
              const SizedBox(width: 8),
            ],
            Text(
              blocked ? 'OUTSIDE WORK ZONE' : widget.label.toUpperCase(),
              style: TextStyle(
                color: blocked ? const Color(0xFF888888) : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GEO-FENCE CUSTOM PAINTER
// ════════════════════════════════════════════════════════════════════════════
class _GeoFencePainter extends CustomPainter {
  final double rotateAngle;
  final double pulse;
  final double glow;
  final double radar;
  final double ripple;
  final bool   outsideRadius;

  const _GeoFencePainter({
    required this.rotateAngle,
    required this.pulse,
    required this.glow,
    required this.radar,
    required this.ripple,
    required this.outsideRadius,
  });

  static const _orange    = Color(0xFFFF5500);
  static const _blackDeep = Color(0xFF040404);
  static const _blackCard = Color(0xFF0D0D0D);
  static const _deny      = Color(0xFFFF2244);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = size.width  / 2;

    final activeColor = outsideRadius ? _deny : _orange;

    // Radial background
    canvas.drawCircle(Offset(cx, cy), r, Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF131313), _blackCard, _blackDeep],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)));

    // Map grid
    final gridPaint = Paint()
      ..color = const Color(0xFFFF5500).withOpacity(0.04)
      ..strokeWidth = 0.5;
    for (int i = -12; i <= 12; i++) {
      canvas.drawLine(Offset(cx + i * 20, 0), Offset(cx + i * 20, size.height), gridPaint);
      canvas.drawLine(Offset(0, cy + i * 20), Offset(size.width, cy + i * 20), gridPaint);
    }

    // Geo-fence zone
    final fenceR = r * 0.44 * pulse;

    canvas.drawCircle(Offset(cx, cy), fenceR, Paint()
      ..color = activeColor.withOpacity(outsideRadius ? 0.04 : 0.07)
      ..style = PaintingStyle.fill);

    canvas.drawCircle(Offset(cx, cy), fenceR + 16, Paint()
      ..color = activeColor.withOpacity(0.05 * glow)
      ..style = PaintingStyle.fill);

    _drawDashedCircle(canvas: canvas, center: Offset(cx, cy), radius: fenceR,
        color: activeColor.withOpacity(0.75), dashLength: 10, gapLength: 6, strokeWidth: 1.8);

    // Radar sweep (inside only)
    if (!outsideRadius) {
      final sweepAngle = radar * 2 * math.pi;
      canvas.drawCircle(Offset(cx, cy), fenceR, Paint()
        ..shader = SweepGradient(
          startAngle: sweepAngle - 1.4,
          endAngle: sweepAngle,
          colors: [Colors.transparent, _orange.withOpacity(0.18)],
          transform: GradientRotation(sweepAngle - 1.4),
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: fenceR)));
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + fenceR * math.cos(sweepAngle), cy + fenceR * math.sin(sweepAngle)),
        Paint()..color = _orange.withOpacity(0.55)..strokeWidth = 1.5,
      );
    }

    // Ripple rings
    for (int i = 0; i < 3; i++) {
      final t = (ripple + i / 3) % 1.0;
      canvas.drawCircle(Offset(cx, cy), fenceR * 0.75 * t, Paint()
        ..color = activeColor.withOpacity((1 - t) * 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }

    // Outside: dashed line + distance tag
    if (outsideRadius) {
      const empAngle = 0.22;
      const empDist  = 0.35;
      final empX  = cx + empDist * size.width  * math.cos(empAngle);
      final empY  = cy + empDist * size.width  * math.sin(empAngle);
      final edgeX = cx + fenceR * math.cos(empAngle);
      final edgeY = cy + fenceR * math.sin(empAngle);

      _drawDashedLine(canvas: canvas, from: Offset(edgeX, edgeY), to: Offset(empX, empY),
          color: _deny.withOpacity(0.65), dashLength: 7, gapLength: 4, strokeWidth: 1.5);

      _paintLabel(canvas, Offset((edgeX + empX) / 2 + 18, (edgeY + empY) / 2 - 4), '1.2 KM', _deny);
    }

    // Outer orbit ring
    _drawDashedCircle(canvas: canvas, center: Offset(cx, cy), radius: r * 0.84,
        color: _orange.withOpacity(0.06), dashLength: 5, gapLength: 9,
        strokeWidth: 1, rotationOffset: rotateAngle);

    // Rotating perimeter dots
    final dotPaint = Paint()..color = _orange.withOpacity(0.2);
    for (int i = 0; i < 6; i++) {
      final a  = rotateAngle + (i * math.pi / 3);
      final dr = r * 0.81;
      canvas.drawCircle(Offset(cx + dr * math.cos(a), cy + dr * math.sin(a)), 2.5, dotPaint);
    }

    // Compass ticks
    final compassPaint = Paint()..color = _orange.withOpacity(0.12)..strokeWidth = 1.5;
    for (int i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      canvas.drawLine(
        Offset(cx + (r * 0.88) * math.cos(a), cy + (r * 0.88) * math.sin(a)),
        Offset(cx + (r * 0.78) * math.cos(a), cy + (r * 0.78) * math.sin(a)),
        compassPaint,
      );
    }
  }

  void _drawDashedCircle({
    required Canvas canvas, required Offset center, required double radius,
    required Color color, required double dashLength, required double gapLength,
    required double strokeWidth, double rotationOffset = 0,
  }) {
    final paint = Paint()
      ..color = color..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final circumference = 2 * math.pi * radius;
    final totalDash = dashLength + gapLength;
    final count = (circumference / totalDash).round();
    for (int i = 0; i < count; i++) {
      final startAngle = rotationOffset + (i * totalDash / radius);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          startAngle, dashLength / radius, false, paint);
    }
  }

  void _drawDashedLine({
    required Canvas canvas, required Offset from, required Offset to,
    required Color color, required double dashLength, required double gapLength,
    required double strokeWidth,
  }) {
    final paint = Paint()..color = color..strokeWidth = strokeWidth..strokeCap = StrokeCap.round;
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist == 0) return;
    final ux = dx / dist;
    final uy = dy / dist;
    double drawn = 0;
    bool drawing = true;
    var p = from;
    while (drawn < dist) {
      final segLen = drawing ? math.min(dashLength, dist - drawn) : math.min(gapLength, dist - drawn);
      final end = Offset(p.dx + ux * segLen, p.dy + uy * segLen);
      if (drawing) canvas.drawLine(p, end, paint);
      p = end; drawn += segLen; drawing = !drawing;
    }
  }

  void _paintLabel(Canvas canvas, Offset pos, String label, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(
          color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: pos,
          width: tp.width + 14, height: tp.height + 8), const Radius.circular(3)),
      Paint()..color = const Color(0xFF040404).withOpacity(0.88),
    );
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_GeoFencePainter old) => true;
}

// ════════════════════════════════════════════════════════════════════════════
// CINEMATIC BACKGROUND
// ════════════════════════════════════════════════════════════════════════════
class _CinematicBackground extends StatelessWidget {
  final Animation<double> rotateAnim;
  final Animation<double> glowAnim;
  const _CinematicBackground({required this.rotateAnim, required this.glowAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([rotateAnim, glowAnim]),
      builder: (_, __) => CustomPaint(
        painter: _CinematicBgPainter(angle: rotateAnim.value, glow: glowAnim.value),
      ),
    );
  }
}

class _CinematicBgPainter extends CustomPainter {
  final double angle;
  final double glow;
  _CinematicBgPainter({required this.angle, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = const Color(0xFFFF5500).withOpacity(0.022)..strokeWidth = 0.5;
    for (int i = 0; i < 22; i++) {
      final x = (size.width / 22) * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (int i = 0; i < 34; i++) {
      final y = (size.height / 34) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFFF5500).withOpacity(0.09 * glow), Colors.transparent],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.12, size.height * 0.18), radius: size.width * 0.5)));

    final ringPaint = Paint()..color = const Color(0xFFFF5500).withOpacity(0.035)
      ..style = PaintingStyle.stroke..strokeWidth = 1;
    final cx = size.width * 0.76;
    final cy = size.height * 0.26;
    canvas.drawCircle(Offset(cx, cy), size.width * 0.3, ringPaint);
    canvas.drawCircle(Offset(cx, cy), size.width * 0.18, ringPaint);

    final dotPaint = Paint()..color = const Color(0xFFFF5500).withOpacity(0.14);
    for (int i = 0; i < 5; i++) {
      final a = angle + (i * 2 * math.pi / 5);
      final r = size.width * 0.24;
      canvas.drawCircle(Offset(cx + r * math.cos(a), cy + r * math.sin(a)), 2.5, dotPaint);
    }

    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45),
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.transparent, const Color(0xFF040404).withOpacity(0.65)],
        ).createShader(Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45)));
  }

  @override
  bool shouldRepaint(_CinematicBgPainter old) => old.angle != angle || old.glow != glow;
}

// ════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final String  label;
  final IconData icon;
  final Color   color;
  const _StatusBadge({super.key, required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 12),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontSize: 10,
          fontWeight: FontWeight.w900, letterSpacing: 1.5)),
    ]),
  );
}

class _ClockInAllowed extends StatelessWidget {
  const _ClockInAllowed({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFFF5500).withOpacity(0.1),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: const Color(0xFFFF5500).withOpacity(0.4)),
      boxShadow: [BoxShadow(color: const Color(0xFFFF5500).withOpacity(0.2), blurRadius: 16)],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7,
          decoration: const BoxDecoration(color: Color(0xFFFF5500), shape: BoxShape.circle)),
      const SizedBox(width: 8),
      const Text('CLOCK-IN AVAILABLE',
          style: TextStyle(color: Color(0xFFFF5500), fontSize: 10,
              fontWeight: FontWeight.w900, letterSpacing: 1.5)),
    ]),
  );
}

class _ClockInDenied extends StatelessWidget {
  const _ClockInDenied({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFFF2244).withOpacity(0.1),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: const Color(0xFFFF2244).withOpacity(0.4)),
      boxShadow: [BoxShadow(color: const Color(0xFFFF2244).withOpacity(0.2), blurRadius: 16)],
    ),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.block_rounded, color: Color(0xFFFF2244), size: 12),
      SizedBox(width: 8),
      Text('OUTSIDE ZONE — DENIED',
          style: TextStyle(color: Color(0xFFFF2244), fontSize: 10,
              fontWeight: FontWeight.w900, letterSpacing: 1.5)),
    ]),
  );
}

class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
          colors: [Color(0xFFFF5500), Color(0xFFCC2200)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(4),
      boxShadow: const [BoxShadow(color: Color(0x66FF5500), blurRadius: 16)],
    ),
    child: const Center(child: Icon(Icons.fingerprint_rounded, color: Colors.white, size: 22)),
  );
}

class _ChipLabel extends StatelessWidget {
  final String label;
  const _ChipLabel({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFFF5500).withOpacity(0.08),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: const Color(0xFFFF5500).withOpacity(0.3), width: 1),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 5, height: 5,
          decoration: const BoxDecoration(color: Color(0xFFFF5500), shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(label.toUpperCase(),
          style: const TextStyle(color: Color(0xFFFF5500), fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 1.5)),
    ]),
  );
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool compact;
  const _PrimaryButton({required this.label, required this.onPressed, this.compact = false});
  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 20 : 30, vertical: widget.compact ? 10 : 15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hovered
                  ? [const Color(0xFFFF7A1A), const Color(0xFFFF3D00)]
                  : [const Color(0xFFFF5500), const Color(0xFFCC2200)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(4),
            boxShadow: _hovered
                ? [BoxShadow(color: const Color(0xFFFF5500).withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 6))]
                : [BoxShadow(color: const Color(0xFFFF5500).withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Text(widget.label.toUpperCase(),
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800,
                  fontSize: widget.compact ? 12 : 13, letterSpacing: 1.2)),
        ),
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  const _GhostButton({required this.label, required this.onPressed});
  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0x1AFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _hovered ? const Color(0x80FFFFFF) : const Color(0x33FFFFFF), width: 1),
          ),
          child: Text(widget.label.toUpperCase(),
              style: TextStyle(
                  color: _hovered ? const Color(0xFFFFFFFF) : const Color(0xCCFFFFFF),
                  fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1.2)),
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _NavLink({required this.label, required this.onTap});
  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.label.toUpperCase(),
                style: TextStyle(
                    color: _hovered ? const Color(0xFFFFFFFF) : const Color(0x80FFFFFF),
                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 1.5, width: _hovered ? 20 : 0, color: const Color(0xFFFF5500),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MobileMenuLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MobileMenuLink({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        Container(width: 3, height: 16, color: const Color(0xFFFF5500)),
        const SizedBox(width: 14),
        Text(label.toUpperCase(),
            style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14,
                fontWeight: FontWeight.w800, letterSpacing: 2)),
      ]),
    ),
  );
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 40, color: const Color(0x1AFFFFFF));
}

class _StatCard extends StatelessWidget {
  final _Stat stat;
  const _StatCard({required this.stat});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(stat.value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900,
                color: Color(0xFFFF5500), letterSpacing: -0.5)),
      ),
      const SizedBox(height: 5),
      Text(stat.label, textAlign: TextAlign.center, maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF),
              fontWeight: FontWeight.w500, height: 1.4, letterSpacing: 0.5)),
    ]),
  );
}

class _FeatureCard extends StatefulWidget {
  final _FeatureItem feature;
  const _FeatureCard({required this.feature});
  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF141414) : const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _hovered ? widget.feature.color.withOpacity(0.5) : const Color(0x1AFFFFFF),
            width: 1,
          ),
          boxShadow: _hovered
              ? [BoxShadow(color: widget.feature.color.withOpacity(0.12), blurRadius: 24, spreadRadius: 2)]
              : [],
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: widget.feature.gradient,
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(4),
              boxShadow: _hovered
                  ? [BoxShadow(color: widget.feature.color.withOpacity(0.4), blurRadius: 16)]
                  : [],
            ),
            child: Icon(widget.feature.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 20),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.feature.label.toUpperCase(),
                  style: TextStyle(
                      color: _hovered ? const Color(0xFFFFFFFF) : const Color(0xCCFFFFFF),
                      fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(widget.feature.detail,
                  style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 12, height: 1.5)),
            ],
          )),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _hovered ? widget.feature.color.withOpacity(0.15) : Colors.transparent,
              border: Border.all(color: _hovered ? widget.feature.color.withOpacity(0.5) : const Color(0x1AFFFFFF)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.arrow_forward_rounded,
                color: _hovered ? widget.feature.color : const Color(0x33FFFFFF), size: 14),
          ),
        ]),
      ),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────
class _FeatureItem {
  final IconData      icon;
  final String        label;
  final String        detail;
  final Color         color;
  final List<Color>   gradient;
  const _FeatureItem({required this.icon, required this.label, required this.detail,
    required this.color, required this.gradient});
}

class _Stat {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});
}