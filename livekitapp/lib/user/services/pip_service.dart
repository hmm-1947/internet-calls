import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PipService {
  PipService._();
  static final instance = PipService._();

  static const _channel = MethodChannel('livekitapp/pip');
  void Function(bool isInPip)? onPipModeChanged;

  /// Mirrors the platform PiP state for widgets outside the call screen, which
  /// have to collapse to the thumbnail layout too.
  final ValueNotifier<bool> isInPip = ValueNotifier<bool>(false);

  bool _initialized = false;

  void Function()? onUserLeaveHint;

  void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipModeChanged') {
        final inPip = call.arguments as bool;
        isInPip.value = inPip;
        onPipModeChanged?.call(inPip);
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
    // The platform stops reporting mode changes once the call is gone, so the
    // flag is cleared here instead of being left stale.
    if (!active) isInPip.value = false;
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
