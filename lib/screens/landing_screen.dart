// lib/screens/landing_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';

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
  late Animation<double> _pulseAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  int _currentFeature = 0;

  final List<_Feature> _features = [
    _Feature(
      icon: '👤',
      title: 'Face Recognition',
      desc: 'Military-grade AI facial biometrics with liveness detection',
      color: AppColors.accent,
    ),
    _Feature(
      icon: '🔐',
      title: 'Fingerprint Auth',
      desc: 'Instant device-native fingerprint verification',
      color: AppColors.accentSecondary,
    ),
    _Feature(
      icon: '📍',
      title: 'Geo-Fencing',
      desc: 'Smart location-based clock-in within designated zones',
      color: AppColors.warning,
    ),
    _Feature(
      icon: '📊',
      title: 'Real-time Analytics',
      desc: 'Live workforce insights and attendance intelligence',
      color: AppColors.success,
    ),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    // Auto-cycle features
    Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        setState(() => _currentFeature = (_currentFeature + 1) % _features.length);
      } else {
        timer.cancel();
      }
    });

    // Verify if user should be redirected
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // 1. Check if session is still valid (auto-login)
    final isValid = await SecurityService.instance.isSessionValid();
    if (isValid) {
      final employeeId = await SecurityService.instance.getCurrentEmployeeId();
      if (employeeId != null && mounted) {
        Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainScreen()));
        return;
      }
    }

    // 2. Check if any account exists in the database
    final employees = await DatabaseService.instance.getAllEmployees();
    if (employees.isNotEmpty && mounted) {
      // Direct to login if accounts exist
      Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientDark),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Column(
                          children: [
                            _buildTopBar(),
                            const SizedBox(height: 10),
                            Expanded(child: _buildHero(constraints.maxHeight)),
                            _buildFeatureCarousel(),
                            _buildBottomCTA(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.gradientPrimary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('H', style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              )),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'HRIS Bio',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const LoginScreen())),
            child: const Text('Sign in',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(double screenHeight) {
    // Dynamic sizing based on screen height
    final double iconSize = screenHeight < 600 ? 100 : 160;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnim.value,
              child: child,
            ),
            child: Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.3), width: 2),
              ),
              child: Center(
                child: Container(
                  width: iconSize * 0.75,
                  height: iconSize * 0.75,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.6), width: 2),
                    gradient: RadialGradient(
                      colors: [
                        AppColors.accent.withValues(alpha: 0.2),
                        AppColors.accentSecondary.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: iconSize * 0.5,
                      height: iconSize * 0.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.gradientPrimary,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.5),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.fingerprint_rounded,
                        color: AppColors.primary,
                        size: iconSize * 0.26,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: screenHeight * 0.04),
          Text(
            'The Future of\nWorkforce Identity',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: screenHeight < 700 ? 28 : 34,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.1,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Smart biometric attendance with AI face recognition,\nreal-time sync, and enterprise-grade security.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: screenHeight < 700 ? 13 : 15,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatChip(label: '99.8%', sub: 'Accuracy'),
              _StatChip(label: '< 1s', sub: 'Auth Time'),
              _StatChip(label: 'AES-256', sub: 'Secure'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCarousel() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 500), // Better for tablets/iPads
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _FeatureCard(
          key: ValueKey(_currentFeature),
          feature: _features[_currentFeature],
        ),
      ),
    );
  }

  Widget _buildBottomCTA() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_features.length, (i) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _currentFeature ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _currentFeature
                      ? AppColors.accent
                      : AppColors.textMuted,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          Container(
            constraints: const BoxConstraints(maxWidth: 500),
            width: double.infinity,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.gradientPrimary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Get Started',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        )),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded,
                        color: AppColors.primary, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Enterprise plan available · ISO 27001 Compliant',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature {
  final String icon;
  final String title;
  final String desc;
  final Color color;
  const _Feature({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
  });
}

class _FeatureCard extends StatelessWidget {
  final _Feature feature;
  const _FeatureCard({super.key, required this.feature});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.gradientCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: feature.color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: feature.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(feature.icon, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feature.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                const SizedBox(height: 4),
                Text(feature.desc,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String sub;
  const _StatChip({required this.label, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              )),
          Text(sub,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              )),
        ],
      ),
    );
  }
}
