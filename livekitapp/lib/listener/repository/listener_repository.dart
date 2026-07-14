import 'dart:convert';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/common/models/auth_response.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';

class ListenerRepository {
  final ApiClient _apiClient = ApiClient();

  Future<AuthResponse> login(String phone, String password) async {
    final response = await _apiClient.post(ApiConstants.listenerLogin, {
      'phone': phone,
      'password': password,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Login failed');
    }
    return AuthResponse.fromJson(data);
  }

  Future<Map<String, dynamic>> getMe(
    String token, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = ListenerDataCache().cachedMe;
      if (cached != null) return cached;
    }
    final response = await _apiClient.get(
      ApiConstants.listenerMe,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load profile');
    }
    ListenerDataCache().setMe(data);
    return data;
  }

  Future<Map<String, dynamic>> getWallet(
    String token, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = ListenerDataCache().cachedWallet;
      if (cached != null) return cached;
    }
    final response = await _apiClient.get(
      ApiConstants.listenerWallet,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load wallet');
    }
    ListenerDataCache().setWallet(data);
    return data;
  }

  Future<void> updateStatus(String token, bool isOnline) async {

    final response = await _apiClient.post(ApiConstants.listenerStatus, {
      'is_online': isOnline,
    }, token: token);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to update status');
    }
  }

  Future<void> updateProfile(
    String token, {
    String? about,
    List<String>? tags,
    List<String>? languages,
  }) async {
    final response = await _apiClient.put(ApiConstants.listenerProfile, {
      if (about != null) 'about': about,
      if (tags != null) 'tags': tags,
      if (languages != null) 'languages': languages,
    }, token: token);
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to update profile');
    }
    ListenerDataCache().invalidateMe();
  }


  Future<void> logout(String token) async {
    final response = await _apiClient.post(
      ApiConstants.listenerLogout,
      {},
      token: token,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Logout failed');
    }
  }

  Future<Map<String, dynamic>> acceptCall(String token, int callId) async {
    final res = await _apiClient.post(
      ApiConstants.callAccept(callId),
      {},
      token: token,
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to accept call');
    }
    return data;
  }

  Future<void> readyCall(String token, int callId) async {
    final res = await _apiClient.post(
      ApiConstants.callReady(callId),
      {},
      token: token,
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to mark call ready');
    }
  }

  Future<void> rejectCall(String token, int callId) async {
    final response = await _apiClient.post(
      ApiConstants.callReject(callId),
      {},
      token: token,
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to reject call');
    }
  }

  Future<void> endCall(String token, int callId) async {
    final response = await _apiClient.post(
      ApiConstants.callEnd(callId),
      {},
      token: token,
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to end call');
    }
  }

  Future<void> updateFcmToken(String token, String fcmToken) async {
    final response = await _apiClient.post(ApiConstants.listenerFcmToken, {
      'fcm_token': fcmToken,
    }, token: token);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to update FCM token');
    }
  }

  Future<Map<String, dynamic>> sendChatMessage(
    String token,
    int userId,
    String message, {
    String? clientId,
  }) async {
    final response = await _apiClient.post(ApiConstants.listenerChatSend, {
      'user_id': userId,
      'message': message,
      'client_id': clientId,
    }, token: token);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to send message');
    }
    ListenerDataCache().invalidateMe();
    ListenerDataCache().invalidateThreads();
    return data;
  }

  Future<Map<String, dynamic>> sendVoiceMessage(
    String token,
    int userId,
    String filePath,
    int duration, {
    String? clientId,
  }) async {
    final response = await _apiClient.postMultipart(
      ApiConstants.listenerChatSendVoice,
      {
        'user_id': userId.toString(),
        'duration': duration.toString(),
        if (clientId != null) 'client_id': clientId,
      },
      filePath,
      'file',
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to send voice message');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> getChatMessages(
    String token,
    int userId,
  ) async {
    final response = await _apiClient.get(
      ApiConstants.listenerMessages(userId),
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load messages');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> markMessagesRead(String token, int userId) async {
    await _apiClient.post(
      ApiConstants.listenerMarkRead(userId),
      {},
      token: token,
    );
  }

  Future<List<Map<String, dynamic>>> getCallHistory(String token) async {
    final response = await _apiClient.get(
      ApiConstants.listenerCallHistory,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load call history');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getChatThreads(
    String token, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = ListenerDataCache().cachedThreads;
      if (cached != null) return cached;
    }
    final response = await _apiClient.get(
      ApiConstants.listenerChatThreads,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load threads');
    }
    final threads = List<Map<String, dynamic>>.from(data);
    ListenerDataCache().setThreads(threads);
    return threads;
  }

  Future<List<Map<String, dynamic>>> getReviews(String token) async {
    final response = await _apiClient.get(
      ApiConstants.listenerReviews,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load reviews');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getUsers(
    String token, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = ListenerDataCache().cachedUsers;
      if (cached != null) return cached;
    }
    final response = await _apiClient.get(
      ApiConstants.listenerUsers,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load users');
    }
    final users = List<Map<String, dynamic>>.from(data);
    ListenerDataCache().setUsers(users);
    return users;
  }

  Future<void> editMessage(String token, int messageId, String message) async {
    final response = await _apiClient.post(ApiConstants.messageEdit, {
      'message_id': messageId,
      'message': message,
    }, token: token);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to edit message');
    }
  }

  Future<void> deleteMessage(String token, int messageId) async {
    final response = await _apiClient.delete(
      ApiConstants.deleteMessage(messageId),
      token: token,
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to delete message');
    }
  }

  Future<void> updateChatSettings(
    String token,
    int otherId, {
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
  }) async {
    final response = await _apiClient.post(ApiConstants.listenerChatSettings, {
      'other_id': otherId,
      'is_pinned': isPinned,
      'is_archived': isArchived,
      'is_muted': isMuted,
    }, token: token);
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to update chat settings');
    }
    ListenerDataCache().invalidateThreads();
  }

  Future<Map<String, dynamic>?> getNoteByCall(String token, int callId) async {
    final response = await _apiClient.get(
      ApiConstants.listenerNoteByCall(callId),
      token: token,
    );
    if (response.statusCode == 404) return null;
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load note');
    }
    return data;
  }

  Future<Map<String, dynamic>?> getNoteByUser(String token, int userId) async {
    final response = await _apiClient.get(
      ApiConstants.listenerNoteByUser(userId),
      token: token,
    );
    if (response.statusCode == 404) return null;
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load note');
    }
    return data;
  }

  Future<void> saveNote(
    String token, {
    int? callId,
    int? userId,
    required String note,
  }) async {
    final response = await _apiClient.post(ApiConstants.listenerNoteSave, {
      if (callId != null) 'call_id': callId,
      if (userId != null) 'user_id': userId,
      'note': note,
    }, token: token);
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to save note');
    }
  }
}
