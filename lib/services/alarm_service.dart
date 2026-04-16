import 'dart:async';
import 'package:flutter/services.dart';
// Note: You need to add flutter_ringtone_player: ^3.2.1 to your pubspec.yaml
// import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  bool _isRinging = false;
  bool get isRinging => _isRinging;

  /// Starts the alarm sound and vibration
  Future<void> startAlarm() async {
    if (_isRinging) return;
    _isRinging = true;
    
    // We use HapticFeedback as a fallback if the library is not yet installed
    // In a real app, you would use FlutterRingtonePlayer.playAlarm()
    _ringLoop();
  }

  /// Stops the alarm
  void stopAlarm() {
    _isRinging = false;
    // FlutterRingtonePlayer.stop();
  }

  void _ringLoop() async {
    while (_isRinging) {
      // Simulate alarm vibration
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 500));
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // If you have flutter_ringtone_player:
      // FlutterRingtonePlayer.play(
      //   android: AndroidSounds.alarm,
      //   ios: IosSounds.alarm,
      //   looping: true,
      //   volume: 1.0,
      // );
    }
  }
}
