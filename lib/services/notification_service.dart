import 'dart:convert';
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
  static const Duration _channelTimeout = Duration(seconds: 2);

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
        await _channel
            .invokeMethod('requestPermission')
            .timeout(_channelTimeout);
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
        }).timeout(_channelTimeout);
      } catch (_) {}
    }
  }

  static Future<void> cancelRideProgress() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel
            .invokeMethod('cancelRideProgress')
            .timeout(_channelTimeout);
      } catch (_) {}
    }
  }

  static Future<void> showCommuteAlert({
    required String type, // 'track', 'stop', 'arrival', 'info'
    required String title,
    required String body,
    bool vibrate = true,
    bool headphoneAudioBypass = true,
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
          'headphoneAudioBypass': headphoneAudioBypass,
        }).timeout(_channelTimeout);
      } catch (_) {}
    }
  }

  /// Starts or updates the Android foreground service that keeps active ride
  /// or track watch alive silently in the background (even if swiped away),
  /// guarded by strict arrival/time cutoffs.
  static Future<void> startBackgroundGuard(Map<String, dynamic> payload) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('startBackgroundGuard', {
          'payloadJson': json.encode(payload),
        }).timeout(_channelTimeout);
      } catch (_) {}
    }
  }

  /// Stops the Android foreground background guard service cleanly.
  static Future<void> stopBackgroundGuard() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel
            .invokeMethod('stopBackgroundGuard')
            .timeout(_channelTimeout);
      } catch (_) {}
    }
  }

  /// Re-attaches UI to the foreground service and retrieves any stop/track
  /// progress or user stop action recorded while the UI was closed.
  static Future<Map<String, dynamic>?> syncBackgroundState() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _channel
            .invokeMethod<Map<dynamic, dynamic>>('syncBackgroundState')
            .timeout(_channelTimeout);
        if (res != null) {
          return Map<String, dynamic>.from(res);
        }
      } catch (_) {}
    }
    return null;
  }

  /// Moves the Android Activity to the background without terminating it,
  /// preventing accidental close when pressing Back during an active ride/watch.
  static Future<void> moveToBackground() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel
            .invokeMethod('moveToBackground')
            .timeout(_channelTimeout);
      } catch (_) {}
    }
  }

  /// Checks whether wired, USB-C, or Bluetooth headphones/earbuds are active.
  static Future<bool> isHeadphonesConnected() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _channel
            .invokeMethod<bool>('isHeadphonesConnected')
            .timeout(_channelTimeout);
        return res == true;
      } catch (_) {}
    }
    return false;
  }
}
