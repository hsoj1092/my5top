import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class InAppAlertEvent {
  final String type; // 'track', 'stop', 'arrival', 'info'
  final String title;
  final String body;
  final DateTime timestamp;

  const InAppAlertEvent({
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
  });
}

class NotificationService {
  static const MethodChannel _channel =
      MethodChannel('com.my5top.commute/notifications');

  static final List<void Function(InAppAlertEvent)> _listeners = [];

  static void addAlertListener(void Function(InAppAlertEvent) listener) {
    _listeners.add(listener);
  }

  static void removeAlertListener(void Function(InAppAlertEvent) listener) {
    _listeners.remove(listener);
  }

  static void _emitInApp(String type, String title, String body) {
    final evt = InAppAlertEvent(
      type: type,
      title: title,
      body: body,
      timestamp: DateTime.now(),
    );
    for (final l in List.of(_listeners)) {
      try {
        l(evt);
      } catch (_) {}
    }
  }

  static Future<void> requestPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('requestPermission');
      } catch (_) {}
    }
  }

  static Future<void> updateRideProgress({
    required String title,
    required String body,
    required String subText,
    required int passedStops,
    required int totalStops,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('showRideProgress', {
          'title': title,
          'body': body,
          'subText': subText,
          'passedStops': passedStops,
          'totalStops': totalStops,
        });
      } catch (_) {}
    }
  }

  static Future<void> cancelRideProgress() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('cancelRideProgress');
      } catch (_) {}
    }
  }

  static Future<void> showCommuteAlert({
    required String type, // 'track', 'stop', 'arrival'
    required String title,
    required String body,
    bool vibrate = true,
  }) async {
    _emitInApp(type, title, body);
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('showAlert', {
          'id': DateTime.now().millisecondsSinceEpoch % 100000,
          'type': type,
          'title': title,
          'body': body,
          'vibrate': vibrate,
        });
      } catch (_) {}
    }
  }
}
