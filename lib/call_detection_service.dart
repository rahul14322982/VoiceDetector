import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the Live Call Detection setting, asks for permissions, and receives
/// the action chosen on the notification. The notification itself is shown by the
/// native CallStateReceiver, so it works even when the app is closed.
/// Recording never starts unless the user taps Allow.
class CallDetectionService {
  CallDetectionService._();
  static final CallDetectionService instance = CallDetectionService._();

  static const _prefKey = 'liveCallDetection';
  static const _channel = MethodChannel('voice_detector/call_action');

  /// Called with 'allow' or 'open' when the user taps the notification.
  void Function(String action)? onAction;

  void listenForActions() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') onAction?.call(call.arguments as String);
    });
  }

  /// Action that launched the app from the notification, if any.
  Future<String?> initialAction() async {
    try {
      return await _channel.invokeMethod<String>('getInitialAction');
    } catch (_) {
      return null;
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Turns the setting off if the phone permission was revoked.
    Future<void> restoreIfEnabled() async {
    if (!await isEnabled()) return;
    if (!await Permission.phone.isGranted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, false);
      return;
    }
    await _service('startService');
  }

  Future<bool> enable() async {
    final phone = await Permission.phone.request(); // READ_PHONE_STATE only
    if (!phone.isGranted) return false;

    final notif = await Permission.notification.request();
    if (!notif.isGranted) return false;

    await Permission.microphone.request(); // so Allow can start recording at once

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    return true;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
  }
  Future<void> _service(String method) async {
    try {
      await _channel.invokeMethod(method);
    } catch (_) {}
  }
}
