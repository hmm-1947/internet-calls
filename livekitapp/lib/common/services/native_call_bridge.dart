import 'package:flutter/services.dart';

/// Hands the Android side the little it needs to finish a call action on its
/// own, and collects the result of the ones it finished.
///
/// When the app has been killed, a lock screen tap happens before any Dart
/// isolate is up to call `/call/{id}/reject` or `/call/{id}/accept`. Native
/// does those requests itself in that case, and needs the session token to
/// authenticate them.
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

  /// LiveKit credentials for a call native already accepted while this engine
  /// was still booting. Returns them once, then native forgets them.
  static Future<Map<String, dynamic>?> takeAcceptedCall() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'takeAcceptedCall',
      );
      if (result == null || result.isEmpty) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Throws away any parked accept. Called whenever Dart has already dealt with
  /// the call itself, so a leftover copy cannot be replayed on a later start.
  static Future<void> clearAcceptedCall() => takeAcceptedCall();

  /// True while native is still waiting on `/call/{id}/accept`. Callers should
  /// hold off on issuing a duplicate request until this clears.
  static Future<bool> isAcceptPending() async {
    try {
      return await _channel.invokeMethod<bool>('isAcceptPending') == true;
    } catch (_) {
      return false;
    }
  }
}
