import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'screens/landing_screen.dart';
import 'screens/admin_dashboard.dart';
import 'firebase_options.dart';
import 'services/database_service.dart';
import 'theme/theme_notifier.dart';
import 'theme/app_theme.dart'; // ← add this

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
    debugPrint('Firebase Initialized Successfully');
  } catch (e) {
    debugPrint('Firebase Initialization Failed/Timed Out: $e');
  }

  if (!kIsWeb) {
    try {
      await DatabaseService.instance.database
          .timeout(const Duration(seconds: 3));
      debugPrint('Local Database Initialized');
    } catch (e) {
      debugPrint('Local DB Init Failed: $e');
    }
  }

  final themeNotifier = ThemeNotifier();

  const String startPage =
  String.fromEnvironment('page', defaultValue: 'landing');
  runApp(MyApp(startPage: startPage, themeNotifier: themeNotifier));
}

class MyApp extends StatelessWidget {
  final String startPage;
  final ThemeNotifier themeNotifier;
  const MyApp({super.key, required this.startPage, required this.themeNotifier});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeNotifier>.value(
      value: themeNotifier,
      child: Consumer<ThemeNotifier>(
        builder: (context, notifier, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'HRIS Biometrics',
            theme: AppTheme.lightTheme,      // ← your full light theme
            darkTheme: AppTheme.darkTheme,   // ← your full dark theme
            themeMode: notifier.themeMode,   // ← switches globally
            home: startPage == 'admin'
                ? const AdminDashboard()
                : const LandingScreen(),
          );
        },
      ),
    );
  }
}