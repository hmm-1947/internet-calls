import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Turns the screen off while the phone is held to the ear during an active
/// voice call, and wakes it immediately when it's moved away.
///
/// Backed by Android's `PROXIMITY_SCREEN_OFF_WAKE_LOCK` — the same mechanism
/// the system Phone app uses — so the OS handles the sensor readings and the
/// screen on/off transitions natively. Nothing here polls the sensor from
/// Dart; this just tells the platform when it's allowed to act on it.
class ProximityService with WidgetsBindingObserver {
  ProximityService._();

  static final ProximityService instance = ProximityService._();

  static const _channel = MethodChannel('livekitapp/proximity');

  bool _active = false;
  bool _observing = false;

  bool get isActive => _active;

  /// Call once a voice call is actually connected. No-ops if already
  /// active, and safe to call repeatedly.
  Future<void> enable() async {
    if (_active) return;
    _ensureObserving();
    try {
      final acquired = await _channel.invokeMethod<bool>('acquire');
      _active = acquired == true;
    } on PlatformException catch (e) {
      debugPrint('ProximityService.enable failed: $e');
      _active = false;
    } catch (e) {
      debugPrint('ProximityService.enable failed: $e');
      _active = false;
    }
  }

  /// Call as soon as the call ends, the call screen is left, or a video call
  /// starts. Safe to call even if never enabled.
  Future<void> disable() async {
    _stopObserving();
    if (!_active) return;
    _active = false;
    try {
      await _channel.invokeMethod('release');
    } catch (e) {
      debugPrint('ProximityService.disable failed: $e');
    }
  }

  void _ensureObserving() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void _stopObserving() {
    if (!_observing) return;
    _observing = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Safety net: if the app is killed in a way that skips the call screen's
  /// normal dispose path, release the wake lock rather than leaving it held
  /// (which could otherwise strand the screen off).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && _active) {
      disable();
    }
  }
}
