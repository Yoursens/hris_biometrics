// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'theme/app_theme.dart';
import 'theme/theme_notifier.dart';
import 'services/database_service.dart';
import 'data/local/dao/connectivity_service.dart';
import 'data/local/dao/sync_service.dart';
import 'screens/landing_screen.dart';
import 'screens/admin_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase first
  try {
    if (kIsWeb) {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: "AIzaSyAIfs300WjCmdeejsEw50lV2VxMjf-5QVg",
            authDomain: "week-9-activity-53484.firebaseapp.com",
            projectId: "week-9-activity-53484",
            storageBucket: "week-9-activity-53484.firebasestorage.app",
            messagingSenderId: "1095102475957",
            appId: "1:1095102475957:web:45a4624634e83b53e4d8fc",
            measurementId: "G-605G4TDLCX",
          ),
        );
      }
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('Firebase Init Error: $e');
  }

  // 2. Initialize Mobile-only services
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await DatabaseService.instance.database;
    await ConnectivityService.instance.init();
    await SyncService.instance.init();
  }

  // 3. Theme logic (Works on both)
  final themeNotifier = ThemeNotifier();
  await themeNotifier.loadFromPrefs();

  runApp(
    ChangeNotifierProvider<ThemeNotifier>.value(
      value: themeNotifier,
      child: const HRISBioApp(),
    ),
  );
}

class HRISBioApp extends StatelessWidget {
  const HRISBioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, _) {
        return MaterialApp(
          title: 'HRIS Master Dashboard',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeNotifier.themeMode,
          // ✅ IF WEB -> SHOW ADMIN DASHBOARD IMMEDIATELY
          home: kIsWeb ? const AdminDashboard() : const SplashScreen(),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _scale = Tween<double>(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.5)));
    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LandingScreen()));
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.gradientDark),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _scale,
                child: FadeTransition(
                  opacity: _fade,
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientPrimary,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 52),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('HRIS Biometrics', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
