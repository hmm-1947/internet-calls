import 'package:flutter/services.dart';

class CallForegroundService {
  CallForegroundService._();
  static final instance = CallForegroundService._();

  static const _channel = MethodChannel('livekitapp/callforeground');

  Future<void> start({String title = 'Ongoing call', bool video = false}) async {
    try {
      await _channel.invokeMethod('start', {'title': title, 'video': video});
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
