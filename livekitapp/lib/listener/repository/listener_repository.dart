import 'dart:convert';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/common/models/auth_response.dart';

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

  Future<Map<String, dynamic>> getMe(String token) async {
    final response = await _apiClient.get(
      ApiConstants.listenerMe,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load profile');
    }
    return data;
  }

  Future<void> updateStatus(String token, bool isOnline) async {
    await _apiClient.post(ApiConstants.listenerStatus, {
      'is_online': isOnline,
    }, token: token);
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
    final res = await _apiClient.post('/call/$callId/accept', {}, token: token);
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to accept call');
    }
    return data;
  }

  Future<void> readyCall(String token, int callId) async {
    final res = await _apiClient.post('/call/$callId/ready', {}, token: token);
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to mark call ready');
    }
  }

  Future<void> rejectCall(String token, int callId) async {
    await _apiClient.post('/call/$callId/reject', {}, token: token);
  }

  Future<void> endCall(String token, int callId) async {
    await _apiClient.post('/call/$callId/end', {}, token: token);
  }

  Future<void> updateFcmToken(String token, String fcmToken) async {
    await _apiClient.post('/listener/fcm-token', {
      "fcm_token": fcmToken,
    }, token: token);
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
      '/chat/listener/$userId/messages',
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load messages');
    }
    return List<Map<String, dynamic>>.from(data);
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

  Future<List<Map<String, dynamic>>> getChatThreads(String token) async {
    final response = await _apiClient.get(
      ApiConstants.listenerChatThreads,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load threads');
    }
    return List<Map<String, dynamic>>.from(data);
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

  Future<List<Map<String, dynamic>>> getUsers(String token) async {
    final response = await _apiClient.get(
      ApiConstants.listenerUsers,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load users');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> editMessage(String token, int messageId, String message) async {
    await _apiClient.post(ApiConstants.messageEdit, {
      'message_id': messageId,
      'message': message,
    }, token: token);
  }

  Future<void> deleteMessage(String token, int messageId) async {
    await _apiClient.delete('/chat/message/$messageId', token: token);
  }

  Future<void> updateChatSettings(
    String token,
    int otherId, {
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
  }) async {
    await _apiClient.post(ApiConstants.listenerChatSettings, {
      'other_id': otherId,
      'is_pinned': isPinned,
      'is_archived': isArchived,
      'is_muted': isMuted,
    }, token: token);
  }
}
