import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'screens/landing_screen.dart';
import 'screens/admin_dashboard.dart';
import 'firebase_options.dart';
import 'services/database_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase with a safety check
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
    debugPrint('Firebase Initialized Successfully');
  } catch (e) {
    debugPrint('Firebase Initialization Failed/Timed Out: $e');
    // We continue so the app doesn't stay on the loading screen
  }

  // 2. Pre-initialize local database (Mobile Only)
  if (!kIsWeb) {
    try {
      await DatabaseService.instance.database.timeout(const Duration(seconds: 3));
      debugPrint('Local Database Initialized');
    } catch (e) {
      debugPrint('Local DB Init Failed: $e');
    }
  }

  const String startPage = String.fromEnvironment('page', defaultValue: 'landing');
  runApp(MyApp(startPage: startPage));
}

class MyApp extends StatelessWidget {
  final String startPage;
  const MyApp({super.key, required this.startPage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HRIS Biometrics',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0F2E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4FF),
          brightness: Brightness.dark,
        ),
      ),
      // Use a consistent starting point
      home: startPage == 'admin' ? const AdminDashboard() : const LandingScreen(),
    );
  }
}
