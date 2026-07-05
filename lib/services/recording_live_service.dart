import 'package:flutter/services.dart';

class RecordingLiveService {
  static const _channel = MethodChannel('focusbell/recording_live');

  static Future<void> start({required String title}) async {
    try {
      await _channel.invokeMethod('start', {'title': title});
    } catch (_) {
      // iOS has no channel handler for this yet — safe no-op.
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
