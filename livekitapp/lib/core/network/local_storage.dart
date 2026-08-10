import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:livekitapp/common/services/native_call_bridge.dart';

class LocalStorage {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'session_token';
  static const _idKey = 'user_id';
  static const _nameKey = 'user_name';

  static String? _token;
  static bool _tokenLoaded = false;
  static Future<String?>? _tokenRead;

  Future<void> saveSession(String token, int id, String name) async {
    _token = token;
    _tokenLoaded = true;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _idKey, value: id.toString());
    await _storage.write(key: _nameKey, value: name);
    // Native declines the call by itself when no isolate is alive to do it.
    await NativeCallBridge.setAuthToken(token);
  }

  Future<String?> getToken() async {
    if (_tokenLoaded) return _token;
    final pending = _tokenRead;
    if (pending != null) return pending;
    final read = _storage.read(key: _tokenKey);
    _tokenRead = read;
    try {
      final value = await read;
      _token = value;
      _tokenLoaded = true;
      return value;
    } finally {
      _tokenRead = null;
    }
  }

  Future<int?> getId() async {
    final value = await _storage.read(key: _idKey);
    return value != null ? int.tryParse(value) : null;
  }

  Future<String?> getName() async {
    return await _storage.read(key: _nameKey);
  }

  Future<void> clear() async {
    _token = null;
    _tokenLoaded = true;
    await _storage.deleteAll();
    await NativeCallBridge.setAuthToken(null);
  }

  static const _activeCallIdKey = 'active_call_id';
  static const _activeCallUrlKey = 'active_call_url';
  static const _activeCallTokenKey = 'active_call_token';
  static const _activeCallVideoKey = 'active_call_video';
  static const _activeCallNameKey = 'active_call_name';
  static const _activeCallPhotoKey = 'active_call_photo';

  Future<void> saveActiveCall(
    int callId,
    String url,
    String token, {
    bool isVideo = false,
    String callerName = 'User',
    String? callerPhotoUrl,
  }) async {
    await _storage.write(key: _activeCallIdKey, value: callId.toString());
    await _storage.write(key: _activeCallUrlKey, value: url);
    await _storage.write(key: _activeCallTokenKey, value: token);
    await _storage.write(key: _activeCallVideoKey, value: isVideo.toString());
    await _storage.write(key: _activeCallNameKey, value: callerName);
    await _storage.write(key: _activeCallPhotoKey, value: callerPhotoUrl ?? '');
  }

  Future<Map<String, dynamic>?> getActiveCall() async {
    final idStr = await _storage.read(key: _activeCallIdKey);
    final url = await _storage.read(key: _activeCallUrlKey);
    final token = await _storage.read(key: _activeCallTokenKey);
    final videoStr = await _storage.read(key: _activeCallVideoKey);
    final callerName = await _storage.read(key: _activeCallNameKey);
    final callerPhotoUrl = await _storage.read(key: _activeCallPhotoKey);
    if (idStr != null && url != null && token != null) {
      final id = int.tryParse(idStr);
      if (id != null) {
        return {
          'callId': id,
          'url': url,
          'token': token,
          'isVideo': videoStr == 'true',
          'callerName': callerName ?? 'User',
          'callerPhotoUrl':
              (callerPhotoUrl != null && callerPhotoUrl.isNotEmpty)
              ? callerPhotoUrl
              : null,
        };
      }
    }
    return null;
  }

  Future<void> clearActiveCall() async {
    await _storage.delete(key: _activeCallIdKey);
    await _storage.delete(key: _activeCallUrlKey);
    await _storage.delete(key: _activeCallTokenKey);
    await _storage.delete(key: _activeCallVideoKey);
    await _storage.delete(key: _activeCallNameKey);
    await _storage.delete(key: _activeCallPhotoKey);
  }

  Future<void> setFlag(String key, bool value) async {
    await _storage.write(key: 'flag_$key', value: value.toString());
  }

  Future<bool> getFlag(String key) async {
    final value = await _storage.read(key: 'flag_$key');
    return value == 'true';
  }

  static const _pendingChatSettingsKey = 'pending_chat_settings_v1';

  /// Chat-settings toggles (favorite/archive/mute) made while offline, keyed
  /// by "ownerType:otherId" so a later toggle on the same thread overwrites
  /// the earlier one instead of piling up duplicate work.
  Future<Map<String, Map<String, dynamic>>> getPendingChatSettings() async {
    final raw = await _storage.read(key: _pendingChatSettingsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAllPendingChatSettings(
    Map<String, Map<String, dynamic>> all,
  ) async {
    if (all.isEmpty) {
      await _storage.delete(key: _pendingChatSettingsKey);
      return;
    }
    await _storage.write(
      key: _pendingChatSettingsKey,
      value: jsonEncode(all),
    );
  }

  /// Merges a toggle into the outbox for "ownerType:otherId", overwriting
  /// only the fields that changed so an earlier queued favorite doesn't get
  /// lost when a later archive toggle is queued for the same thread.
  Future<void> queuePendingChatSettings(
    String ownerType,
    int otherId, {
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
  }) async {
    final all = await getPendingChatSettings();
    final key = '$ownerType:$otherId';
    final existing = all[key] ?? <String, dynamic>{'other_id': otherId};
    if (isPinned != null) existing['is_pinned'] = isPinned;
    if (isArchived != null) existing['is_archived'] = isArchived;
    if (isMuted != null) existing['is_muted'] = isMuted;
    all[key] = existing;
    await _saveAllPendingChatSettings(all);
  }

  Future<void> clearPendingChatSettings(String ownerType, int otherId) async {
    final all = await getPendingChatSettings();
    if (all.remove('$ownerType:$otherId') == null) return;
    await _saveAllPendingChatSettings(all);
  }
}
