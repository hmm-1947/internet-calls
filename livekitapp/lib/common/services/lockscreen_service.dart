import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LockscreenService {
  LockscreenService._();

  static final LockscreenService instance = LockscreenService._();

  static const _channel = MethodChannel('livekitapp/lockscreen');

  final ValueNotifier<bool> isLocked = ValueNotifier<bool>(false);

  bool _initialised = false;

  bool get locked => isLocked.value;

  void init() {
    if (_initialised) return;
    _initialised = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLockStateChanged') {
        isLocked.value = call.arguments == true;
      }
      return null;
    });
    _refreshUntilAnswered();
  }

  Future<void> _refreshUntilAnswered({int attempts = 5}) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (await refresh()) return;
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  Future<bool> refresh() async {
    try {
      final locked = await _channel.invokeMethod<bool>('isDeviceLocked');
      isLocked.value = locked == true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setCallActive(bool active) async {
    try {
      await _channel.invokeMethod('setCallActive', active);
    } catch (_) {}
    await refresh();
  }

  Future<void> showOverLockscreen() => setCallActive(true);

  Future<void> hideOverLockscreen() => setCallActive(false);

  Future<void> leaveLockscreen() async {
    try {
      await _channel.invokeMethod('leaveLockscreen');
    } catch (_) {}
    await refresh();
  }

  Future<void> dismissIncomingCall() async {
    try {
      await _channel.invokeMethod('dismissIncomingCall');
    } catch (_) {}
  }

  Future<bool> requestUnlock() async {
    if (!isLocked.value) return true;
    try {
      final unlocked = await _channel.invokeMethod<bool>('requestUnlock');
      await refresh();
      return unlocked == true;
    } catch (_) {
      return false;
    }
  }
}
