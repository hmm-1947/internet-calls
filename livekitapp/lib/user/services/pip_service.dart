import 'package:flutter/services.dart';

class PipService {
  PipService._();
  static final instance = PipService._();

  static const _channel = MethodChannel('livekitapp/pip');
  void Function(bool isInPip)? onPipModeChanged;

  bool _initialized = false;

  void Function()? onUserLeaveHint;

  void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipModeChanged') {
        onPipModeChanged?.call(call.arguments as bool);
      } else if (call.method == 'onUserLeaveHint') {
        onUserLeaveHint?.call();
      }
    });
  }

  Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isPipSupported');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setCallActive(bool active) async {
    try {
      await _channel.invokeMethod('setCallActive', active);
    } catch (_) {}
  }

  Future<bool> enterPip() async {
    try {
      final result = await _channel.invokeMethod<bool>('enterPip');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
