import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalStorage {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'session_token';
  static const _idKey = 'user_id';
  static const _nameKey = 'user_name';

  Future<void> saveSession(String token, int id, String name) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _idKey, value: id.toString());
    await _storage.write(key: _nameKey, value: name);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<int?> getId() async {
    final value = await _storage.read(key: _idKey);
    return value != null ? int.tryParse(value) : null;
  }

  Future<String?> getName() async {
    return await _storage.read(key: _nameKey);
  }

  Future<void> clear() async {
    await _storage.deleteAll();
  }

  static const _activeCallIdKey = 'active_call_id';
  static const _activeCallUrlKey = 'active_call_url';
  static const _activeCallTokenKey = 'active_call_token';
  static const _activeCallVideoKey = 'active_call_video';
  static const _activeCallNameKey = 'active_call_name';

  Future<void> saveActiveCall(
    int callId,
    String url,
    String token, {
    bool isVideo = false,
    String callerName = 'User',
  }) async {
    await _storage.write(key: _activeCallIdKey, value: callId.toString());
    await _storage.write(key: _activeCallUrlKey, value: url);
    await _storage.write(key: _activeCallTokenKey, value: token);
    await _storage.write(key: _activeCallVideoKey, value: isVideo.toString());
    await _storage.write(key: _activeCallNameKey, value: callerName);
  }

  Future<Map<String, dynamic>?> getActiveCall() async {
    final idStr = await _storage.read(key: _activeCallIdKey);
    final url = await _storage.read(key: _activeCallUrlKey);
    final token = await _storage.read(key: _activeCallTokenKey);
    final videoStr = await _storage.read(key: _activeCallVideoKey);
    final callerName = await _storage.read(key: _activeCallNameKey);
    if (idStr != null && url != null && token != null) {
      final id = int.tryParse(idStr);
      if (id != null) {
        return {
          'callId': id,
          'url': url,
          'token': token,
          'isVideo': videoStr == 'true',
          'callerName': callerName ?? 'User',
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
  }
}
