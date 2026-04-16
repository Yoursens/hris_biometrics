import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'database_service.dart';
import 'geofence_service.dart';
import 'alarm_service.dart';
import 'security_service.dart';

class AppBackgroundService {
  static const notificationId = 888;
  static const notificationChannelId = 'hris_foreground';

  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'HRIS Background Service',
      description: 'Monitoring attendance and location.',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'HRIS Active',
        initialNotificationContent: 'Monitoring status...',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    service.startService();
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    Timer.periodic(const Duration(minutes: 5), (timer) async {
      final now = DateTime.now();
      
      // CONDITION 1: Before 8:00 PM (20:00)
      if (now.hour >= 20) return;

      final empId = await SecurityService.instance.getCurrentEmployeeId();
      if (empId == null) return;

      final todayAtt = await DatabaseService.instance.getTodayAttendance(empId);
      final isClockedIn = todayAtt?.isClockedIn ?? false;

      // CONDITION 2: Not clocked in
      if (!isClockedIn) {
        final geo = GeofenceService.instance;
        final geoResult = await geo.checkGeofence();

        // CONDITION 3: Outside radius
        if (!geoResult.isInside) {
          // Trigger Alarm even if app is closed
          AlarmService.instance.startAlarm();

          flutterLocalNotificationsPlugin.show(
            notificationId,
            'ATTENTION: Alarm Triggered',
            'You are outside the radius and not timed in before 8 PM. Please open the app and stop the alarm.',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                notificationChannelId,
                'HRIS Background Service',
                icon: 'ic_bg_service_small',
                ongoing: true,
                importance: Importance.max,
                priority: Priority.high,
              ),
            ),
          );
        }
      }
    });
  }
}
