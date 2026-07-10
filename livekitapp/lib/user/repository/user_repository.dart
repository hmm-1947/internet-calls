import 'dart:convert';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/common/models/auth_response.dart';

class UserRepository {
  final ApiClient _apiClient = ApiClient();

  Future<void> registerInitiate(
    String name,
    String email,
    String phone,
    String password,
  ) async {
    final response = await _apiClient.post(ApiConstants.userRegisterInitiate, {
      'name': name,
      'email': email,
      'phone': phone,
      'password': password,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Registration failed');
    }
  }

  Future<AuthResponse> registerVerifyOtp(String email, String otpCode) async {
    final response = await _apiClient.post(ApiConstants.userRegisterVerifyOtp, {
      'email': email,
      'otp_code': otpCode,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'OTP verification failed');
    }
    return AuthResponse.fromJson(data);
  }

  Future<AuthResponse> login(String phone, String password) async {
    final response = await _apiClient.post(ApiConstants.userLogin, {
      'phone': phone,
      'password': password,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Login failed');
    }
    return AuthResponse.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> getListeners(String token) async {
    final response = await _apiClient.get(
      ApiConstants.userListeners,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load listeners');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> initiateCall(
    String token,
    int listenerId, {
    String callType = 'audio',
  }) async {
    final response = await _apiClient.post(ApiConstants.callInitiate, {
      'listener_id': listenerId,
      'call_type': callType,
    }, token: token);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Call failed');
    }
    return data;
  }

  Future<void> startRecording(String token, int callId) async {
    final response = await _apiClient.post(
      '/call/$callId/recording/start',
      {},
      token: token,
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to start recording');
    }
  }

  Future<void> cancelCall(String token, int callId) async {
    final response = await _apiClient.post(
      '/call/$callId/cancel',
      {},
      token: token,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to cancel call');
    }
  }

  Future<void> endCall(String token, int callId) async {
    final response = await _apiClient.post(
      '/call/$callId/end',
      {},
      token: token,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to end call');
    }
  }

  Future<void> reportCoinExceeded(String token, int callId) async {
    final response = await _apiClient.post(
      '/call/$callId/coin-exceeded',
      {},
      token: token,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to report coin exceeded');
    }
  }

  Future<void> updateStatus(String token, bool isOnline) async {
    final response = await _apiClient.post(ApiConstants.userStatus, {
      'is_online': isOnline,
    }, token: token);
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to update status');
    }
  }

  Future<void> updateFcmToken(String token, String fcmToken) async {
    final response = await _apiClient.post('/user/fcm-token', {
      'fcm_token': fcmToken,
    }, token: token);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to update FCM token');
    }
  }

  Future<Map<String, dynamic>> sendChatMessage(
    String token,
    int listenerId,
    String message, {
    String? clientId,
  }) async {
    final response = await _apiClient.post(ApiConstants.userChatSend, {
      'listener_id': listenerId,
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
    int listenerId,
    String filePath,
    int duration, {
    String? clientId,
  }) async {
    final response = await _apiClient.postMultipart(
      ApiConstants.userChatSendVoice,
      {
        'listener_id': listenerId.toString(),
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
    int listenerId,
  ) async {
    final response = await _apiClient.get(
      '/chat/user/$listenerId/messages',
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load messages');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getChatThreads(String token) async {
    final response = await _apiClient.get(
      ApiConstants.userChatThreads,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load threads');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getCallHistory(String token) async {
    final response = await _apiClient.get(
      ApiConstants.userCallHistory,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load call history');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> getCallSummary(String token, int callId) async {
    final response = await _apiClient.get(
      ApiConstants.callSummary(callId),
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load call summary');
    }
    return data;
  }

  Future<void> rateCall(
    String token,
    int callId,
    int rating,
    String review,
  ) async {
    final response = await _apiClient.post(ApiConstants.callRate(callId), {
      'rating': rating,
      'review': review,
    }, token: token);
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to rate call');
    }
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
      '/chat/message/$messageId',
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
    final response = await _apiClient.post(ApiConstants.userChatSettings, {
      'other_id': otherId,
      'is_pinned': isPinned,
      'is_archived': isArchived,
      'is_muted': isMuted,
    }, token: token);
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to update chat settings');
    }
  }

  Future<Map<String, dynamic>> getMe(String token) async {
    final response = await _apiClient.get('/user/me', token: token);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load profile');
    }
    return data;
  }
}
