import 'package:flutter/services.dart';

class CallForegroundService {
  CallForegroundService._();
  static final instance = CallForegroundService._();

  static const _channel = MethodChannel('livekitapp/callforeground');

  Future<void> start({String title = 'Ongoing call'}) async {
    try {
      await _channel.invokeMethod('start', {'title': title});
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
