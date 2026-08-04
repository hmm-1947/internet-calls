import 'package:flutter/services.dart';

/// Hands the Android side the little it needs to finish a call action on its
/// own.
///
/// When the app has been killed, a decline tapped on the lock screen can happen
/// before any Dart isolate is up to call `/call/{id}/reject`, which leaves the
/// caller ringing. Native does that request itself in that case, and needs the
/// session token to authenticate it.
class NativeCallBridge {
  NativeCallBridge._();

  static const _channel = MethodChannel('livekitapp/lockscreen');

  /// Pass `null` to drop the mirrored token, e.g. on logout.
  static Future<void> setAuthToken(String? token) async {
    try {
      await _channel.invokeMethod('setAuthToken', token);
    } catch (_) {
      // No activity attached (background isolate) or another flavor without the
      // handler: the token is pushed again on the next app start.
    }
  }
}
