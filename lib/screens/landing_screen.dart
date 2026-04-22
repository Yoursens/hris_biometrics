// lib/screens/landing_screen.dart
import 'dart:async';
import 'login_screen.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _rotateController;
  late AnimationController _featureSlideController;

  late Animation<double> _pulseAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _rotateAnim;
  late Animation<Offset> _featureSlideAnim;
  late Animation<double> _featureFadeAnim;

  int _currentFeature = 0;
  int _previousFeature = 0;
  Timer? _featureTimer;
  bool _menuOpen = false;

  // --- Design Tokens ---
  static const Color _navy = Color(0xFF0A0F2E);
  static const Color _navyLight = Color(0xFF131A45);
  static const Color _accent = Color(0xFF00D4FF);
  static const Color _accentGlow = Color(0xFF0099BB);
  static const Color _gold = Color(0xFFFFBB00);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _white70 = Color(0xB3FFFFFF);
  static const Color _white40 = Color(0x66FFFFFF);
  static const Color _white15 = Color(0x26FFFFFF);
  static const Color _white08 = Color(0x14FFFFFF);
  static const Color _success = Color(0xFF00E5A0);
  static const Color _warning = Color(0xFFFF6B35);

  final List<_FeatureItem> _features = [
    _FeatureItem(
      icon: Icons.face_retouching_natural_outlined,
      label: 'Face Recognition',
      detail: 'AI-powered facial biometrics with 99.7% accuracy',
      color: _accent,
      gradient: [Color(0xFF00D4FF), Color(0xFF0066CC)],
    ),
    _FeatureItem(
      icon: Icons.my_location_rounded,
      label: 'Geo-Fencing',
      detail: 'Precision GPS clock-in within defined site boundaries',
      color: _success,
      gradient: [Color(0xFF00E5A0), Color(0xFF006644)],
    ),
    _FeatureItem(
      icon: Icons.fingerprint_rounded,
      label: 'Fingerprint Auth',
      detail: 'Hardware-level biometric security on every device',
      color: _gold,
      gradient: [Color(0xFFFFBB00), Color(0xFFCC6600)],
    ),
    _FeatureItem(
      icon: Icons.cloud_sync_rounded,
      label: 'Real-Time Sync',
      detail: 'Instant cross-platform attendance data sync',
      color: _warning,
      gradient: [Color(0xFFFF6B35), Color(0xFFCC2200)],
    ),
  ];

  final List<_Stat> _stats = [
    _Stat(value: '99.7%', label: 'Face Match Accuracy'),
    _Stat(value: '<0.3s', label: 'Auth Speed'),
    _Stat(value: '500K+', label: 'Daily Check-ins'),
    _Stat(value: '99.9%', label: 'Uptime SLA'),
  ];

  @override
  void initState() {
    super.initState();

    // 1. Initialize Controllers
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _featureSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 2. Initialize Animations (MUST be before controllers start)
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotateAnim = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _rotateController, curve: Curves.linear),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _featureSlideAnim = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _featureSlideController, curve: Curves.easeOutCubic));

    _featureFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _featureSlideController, curve: Curves.easeOut),
    );

    // 3. Start Controllers
    _pulseController.repeat(reverse: true);
    _rotateController.repeat();
    _fadeController.forward();
    _slideController.forward();
    _featureSlideController.forward();

    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ));
    }

    _featureTimer = Timer.periodic(const Duration(seconds: 4), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _previousFeature = _currentFeature;
        _currentFeature = (_currentFeature + 1) % _features.length;
      });
      _featureSlideController.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _featureSlideController.dispose();
    _featureTimer?.cancel();
    super.dispose();
  }

  void _onGetStarted() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _onSignIn() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 860;

    return Scaffold(
      backgroundColor: _navy,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            // Background: animated orbit rings
            Positioned.fill(child: _BackgroundOrbit(rotateAnim: _rotateAnim)),

            // Main content
            SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildNavbar(isMobile),
                    isMobile
                        ? _buildMobileHero()
                        : _buildWebHero(),
                    _buildStatsRow(isMobile),
                    _buildFeaturesSection(isMobile),
                    _buildCTASection(isMobile),
                    _buildFooter(isMobile),
                  ],
                ),
              ),
            ),

            // Mobile menu overlay
            if (_menuOpen && isMobile) _buildMobileMenu(),
          ],
        ),
      ),
    );
  }

  // ── NAVBAR ──────────────────────────────────────────────────────────────
  Widget _buildNavbar(bool isMobile) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: _navy.withOpacity(0.85),
        border: Border(bottom: BorderSide(color: _white15, width: 0.5)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                // Logo
                _LogoMark(),
                const SizedBox(width: 14),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HRIS', style: TextStyle(color: _white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 1.5)),
                    Text('BIOMETRICS', style: TextStyle(color: _accent, fontWeight: FontWeight.w700, fontSize: 9, letterSpacing: 3)),
                  ],
                ),

                const Spacer(),

                if (!isMobile) ...[
                  _NavLink(label: 'Features', onTap: () {}),
                  _NavLink(label: 'Pricing', onTap: () {}),
                  _NavLink(label: 'Docs', onTap: () {}),
                  const SizedBox(width: 16),
                  _PrimaryButton(label: 'Sign In', onPressed: _onSignIn, compact: true),
                ] else
                  GestureDetector(
                    onTap: () => setState(() => _menuOpen = !_menuOpen),
                    child: Icon(_menuOpen ? Icons.close : Icons.menu, color: _white),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── MOBILE MENU ─────────────────────────────────────────────────────────
  Widget _buildMobileMenu() {
    return Positioned(
      top: 68,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: _navyLight,
          border: Border(bottom: BorderSide(color: _white15, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MobileMenuLink(label: 'Features', onTap: () => setState(() => _menuOpen = false)),
            _MobileMenuLink(label: 'Pricing', onTap: () => setState(() => _menuOpen = false)),
            _MobileMenuLink(label: 'Docs', onTap: () => setState(() => _menuOpen = false)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _PrimaryButton(label: 'Sign In', onPressed: () { setState(() => _menuOpen = false); _onSignIn(); }),
            ),
          ],
        ),
      ),
    );
  }

  // ── WEB HERO ────────────────────────────────────────────────────────────
  Widget _buildWebHero() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 80),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left: text
              Expanded(
                flex: 55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChipLabel(label: 'Enterprise Attendance Platform'),
                    const SizedBox(height: 28),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: _white, height: 1.1, letterSpacing: -1.5),
                        children: [
                          TextSpan(text: 'Next-Gen\n'),
                          TextSpan(text: 'Biometric\n', style: TextStyle(color: _accent)),
                          TextSpan(text: 'Attendance'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Unify face recognition, fingerprint, and GPS geo-fencing across all devices. Real-time sync. Zero friction.',
                      style: TextStyle(fontSize: 17, color: _white70, height: 1.7, fontWeight: FontWeight.w300),
                    ),
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        _PrimaryButton(label: 'Get Started Free', onPressed: _onGetStarted),
                        const SizedBox(width: 16),
                        _GhostButton(label: 'Watch Demo', onPressed: () {}),
                      ],
                    ),
                    const SizedBox(height: 60),
                    _buildFeatureCarousel(isMobile: false),
                  ],
                ),
              ),

              const SizedBox(width: 60),

              // Right: biometric orb
              Expanded(
                flex: 45,
                child: _BiometricOrb(pulseAnim: _pulseAnim, rotateAnim: _rotateAnim),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── MOBILE HERO ─────────────────────────────────────────────────────────
  Widget _buildMobileHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          _ChipLabel(label: 'Enterprise Attendance Platform'),
          const SizedBox(height: 28),
          _BiometricOrb(pulseAnim: _pulseAnim, rotateAnim: _rotateAnim, size: 220),
          const SizedBox(height: 36),
          RichText(
            textAlign: TextAlign.center,
            text: const TextSpan(
              style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: _white, height: 1.15, letterSpacing: -1),
              children: [
                TextSpan(text: 'Next-Gen '),
                TextSpan(text: 'Biometric\n', style: TextStyle(color: _accent)),
                TextSpan(text: 'Attendance'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Unify face recognition, fingerprint, and GPS geo-fencing across all devices. Real-time sync. Zero friction.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: _white70, height: 1.65, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(label: 'Get Started Free', onPressed: _onGetStarted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _GhostButton(label: 'Watch Demo', onPressed: () {}),
          ),
          const SizedBox(height: 40),
          _buildFeatureCarousel(isMobile: true),
        ],
      ),
    );
  }

  // ── FEATURE CAROUSEL ────────────────────────────────────────────────────
  Widget _buildFeatureCarousel({required bool isMobile}) {
    final feature = _features[_currentFeature];
    return Column(
      crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        // Dot indicators
        Row(
          mainAxisAlignment: isMobile ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: List.generate(_features.length, (i) {
            final active = i == _currentFeature;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 6),
              width: active ? 24 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? _accent : _white40,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),

        // Animated feature card
        AnimatedBuilder(
          animation: _featureSlideController,
          builder: (_, __) => FadeTransition(
            opacity: _featureFadeAnim,
            child: SlideTransition(
              position: _featureSlideAnim,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _white08,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: feature.color.withOpacity(0.3), width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: feature.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(feature.icon, color: _white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(feature.label, style: const TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(feature.detail, style: TextStyle(color: _white70, fontSize: 13, height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── STATS ROW ───────────────────────────────────────────────────────────
  Widget _buildStatsRow(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: _white15, width: 0.5)),
        color: _white08,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 48, vertical: 24),
            child: isMobile
                ? Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _StatCard(stat: _stats[0])),
                    Expanded(child: _StatCard(stat: _stats[1])),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _StatCard(stat: _stats[2])),
                    Expanded(child: _StatCard(stat: _stats[3])),
                  ],
                ),
              ],
            )
                : Row(
              children: _stats.map((s) => Expanded(child: _StatCard(stat: s))).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── FEATURES SECTION ────────────────────────────────────────────────────
  Widget _buildFeaturesSection(bool isMobile) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: 72),
          child: Column(
            children: [
              _SectionLabel(label: 'Platform Features'),
              const SizedBox(height: 16),
              Text(
                'Everything you need for enterprise attendance',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: isMobile ? 28 : 36, fontWeight: FontWeight.w800, color: _white, letterSpacing: -0.5),
              ),
              const SizedBox(height: 48),
              isMobile
                  ? Column(children: _features.map((f) => Padding(padding: const EdgeInsets.only(bottom: 16), child: _FeatureCard(feature: f))).toList())
                  : GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 2.4,
                ),
                itemCount: _features.length,
                itemBuilder: (_, i) => _FeatureCard(feature: _features[i]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── CTA SECTION ─────────────────────────────────────────────────────────
  Widget _buildCTASection(bool isMobile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Container(
            padding: EdgeInsets.all(isMobile ? 36 : 60),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_accent.withOpacity(0.15), _navyLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _accent.withOpacity(0.3), width: 1),
            ),
            child: Column(
              children: [
                Text(
                  'Start securing attendance today',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: isMobile ? 26 : 36, fontWeight: FontWeight.w800, color: _white, letterSpacing: -0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Deploy in minutes. No hardware required. Works on any device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white70, fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 32),
                isMobile
                    ? Column(
                  children: [
                    SizedBox(width: double.infinity, child: _PrimaryButton(label: 'Get Started Free', onPressed: _onGetStarted)),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: _GhostButton(label: 'Contact Sales', onPressed: () {})),
                  ],
                )
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PrimaryButton(label: 'Get Started Free', onPressed: _onGetStarted),
                    const SizedBox(width: 16),
                    _GhostButton(label: 'Contact Sales', onPressed: () {}),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── FOOTER ──────────────────────────────────────────────────────────────
  Widget _buildFooter(bool isMobile) {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: 32),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _white15, width: 0.5)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: isMobile
              ? Column(
            children: [
              _LogoMark(),
              const SizedBox(height: 16),
              Text('© 2025 HRIS Biometrics. All rights reserved.', style: TextStyle(color: _white40, fontSize: 12)),
              const SizedBox(height: 8),
              Text('v2.0 · Cross-Platform Ready', style: TextStyle(color: _white40, fontSize: 11)),
            ],
          )
              : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                _LogoMark(),
                const SizedBox(width: 12),
                Text('HRIS Biometrics', style: TextStyle(color: _white70, fontWeight: FontWeight.w600)),
              ]),
              Text('© 2025 HRIS Biometrics. All rights reserved.', style: TextStyle(color: _white40, fontSize: 12)),
              Text('v2.0 · Cross-Platform Ready', style: TextStyle(color: _white40, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── BIOMETRIC ORB ─────────────────────────────────────────────────────────
class _BiometricOrb extends StatelessWidget {
  final Animation<double> pulseAnim;
  final Animation<double> rotateAnim;
  final double size;

  const _BiometricOrb({required this.pulseAnim, required this.rotateAnim, this.size = 300});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pulseAnim, rotateAnim]),
      builder: (_, __) {
        return SizedBox(
          width: size + 60,
          height: size + 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer spinning ring
              Transform.rotate(
                angle: rotateAnim.value,
                child: CustomPaint(
                  size: Size(size + 60, size + 60),
                  painter: _OrbitRingPainter(
                    color: const Color(0xFF00D4FF),
                    dashCount: 24,
                    dashLength: 8,
                    gapLength: 8,
                  ),
                ),
              ),
              // Inner counter-rotating ring
              Transform.rotate(
                angle: -rotateAnim.value * 0.7,
                child: CustomPaint(
                  size: Size(size + 20, size + 20),
                  painter: _OrbitRingPainter(
                    color: const Color(0xFFFFBB00),
                    dashCount: 16,
                    dashLength: 6,
                    gapLength: 12,
                  ),
                ),
              ),
              // Pulsing glow orb
              Transform.scale(
                scale: pulseAnim.value,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF00D4FF).withOpacity(0.25),
                        const Color(0xFF0A0F2E).withOpacity(0.9),
                      ],
                    ),
                    border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.6), width: 1.5),
                  ),
                  child: const Center(
                    child: Icon(Icons.fingerprint_rounded, size: 130, color: Color(0xFF00D4FF)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── BACKGROUND ORBIT PAINTER ──────────────────────────────────────────────
class _BackgroundOrbit extends StatelessWidget {
  final Animation<double> rotateAnim;
  const _BackgroundOrbit({required this.rotateAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: rotateAnim,
      builder: (_, __) => CustomPaint(
        painter: _BgOrbitPainter(angle: rotateAnim.value),
      ),
    );
  }
}

class _BgOrbitPainter extends CustomPainter {
  final double angle;
  _BgOrbitPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.38;

    // Large ambient ring
    final ringPaint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), size.width * 0.6, ringPaint);
    canvas.drawCircle(Offset(cx, cy), size.width * 0.4, ringPaint);

    // Rotating dots
    final dotPaint = Paint()..color = const Color(0xFF00D4FF).withOpacity(0.12);
    for (int i = 0; i < 6; i++) {
      final a = angle + (i * math.pi / 3);
      final r = size.width * 0.48;
      canvas.drawCircle(
        Offset(cx + r * math.cos(a), cy + r * math.sin(a)),
        3,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_BgOrbitPainter old) => old.angle != angle;
}

// ── ORBIT RING PAINTER ────────────────────────────────────────────────────
class _OrbitRingPainter extends CustomPainter {
  final Color color;
  final int dashCount;
  final double dashLength;
  final double gapLength;

  _OrbitRingPainter({required this.color, required this.dashCount, required this.dashLength, required this.gapLength});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 2;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final circumference = 2 * math.pi * radius;
    final totalDash = dashLength + gapLength;
    final count = (circumference / totalDash).round();

    for (int i = 0; i < count; i++) {
      final startAngle = (i * totalDash / radius);
      final sweepAngle = dashLength / radius;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitRingPainter old) => false;
}

// ── REUSABLE WIDGETS ──────────────────────────────────────────────────────
class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00D4FF), Color(0xFF0055BB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Icon(Icons.fingerprint_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  final String label;
  const _ChipLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00D4FF).withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF00D4FF), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => _ChipLabel(label: label);
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
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 20 : 28, vertical: widget.compact ? 10 : 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hovered
                  ? [const Color(0xFF00EEFF), const Color(0xFF0088DD)]
                  : [const Color(0xFF00D4FF), const Color(0xFF0066CC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: _hovered
                ? [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 6))]
                : [],
          ),
          child: Text(
            widget.label,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: widget.compact ? 14 : 15),
          ),
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
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered ? _LandingScreenState._white15 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _LandingScreenState._white40, width: 1),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(color: _LandingScreenState._white, fontWeight: FontWeight.w600, fontSize: 15),
          ),
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
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _hovered ? _LandingScreenState._white : _LandingScreenState._white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(label, style: const TextStyle(color: _LandingScreenState._white, fontSize: 17, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final _Stat stat;
  const _StatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              stat.value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF00D4FF),
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stat.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: _LandingScreenState._white40, fontWeight: FontWeight.w500, height: 1.3),
          ),
        ],
      ),
    );
  }
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
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _hovered ? _LandingScreenState._white15 : _LandingScreenState._white08,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered ? widget.feature.color.withOpacity(0.5) : _LandingScreenState._white15,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: widget.feature.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(widget.feature.icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.feature.label,
                    style: const TextStyle(color: _LandingScreenState._white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.feature.detail,
                    style: TextStyle(color: _LandingScreenState._white70, fontSize: 13, height: 1.45),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: _LandingScreenState._white40, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── DATA MODELS ───────────────────────────────────────────────────────────
class _FeatureItem {
  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  final List<Color> gradient;
  const _FeatureItem({required this.icon, required this.label, required this.detail, required this.color, required this.gradient});
}

class _Stat {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});
}
