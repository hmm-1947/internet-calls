import 'dart:convert';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/common/models/auth_response.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/user_data_cache.dart';

class InsufficientCoinsException implements Exception {
  final String message;

  const InsufficientCoinsException([
    this.message = 'Not enough coins to send this message',
  ]);

  @override
  String toString() => message;
}

/// Result of a sign-up availability lookup (username or email/phone).
/// [reason] is a user-facing message explaining why it cannot be used, null
/// when available.
class AvailabilityResult {
  final bool available;
  final String? reason;

  const AvailabilityResult({required this.available, this.reason});
}

/// Outcome of sign-up step 1: the backend has texted a code to the number.
class SignupStart {
  /// The number as the backend stored it: the bare 10 digits. Every later
  /// step must send this value.
  final String identifier;
  final bool otpSent;

  const SignupStart({required this.identifier, required this.otpSent});
}

/// Outcome of a Google sign-in. [profileComplete] is false the first time an
/// account is created, which is what sends the app to the profile setup
/// screen to collect a photo, username and display name.
class GoogleAuthResult {
  final AuthResponse auth;
  final bool profileComplete;

  const GoogleAuthResult({required this.auth, required this.profileComplete});
}

class UserRepository {
  final ApiClient _apiClient = ApiClient();

  /// Checked before requesting an OTP so we never send a code to a phone
  /// number that already has an account.
  Future<AvailabilityResult> checkIdentifierAvailable(String identifier) async {
    final response = await _apiClient.get(
      '${ApiConstants.userIdentifierAvailable}'
      '?identifier=${Uri.encodeQueryComponent(identifier)}',
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Could not check this phone number');
    }
    return AvailabilityResult(
      available: data['available'] == true,
      reason: data['reason'] as String?,
    );
  }

  /// Asks the backend whether [username] can still be claimed. Returns the
  /// reason (already taken, invalid format, ...) when it cannot.
  ///
  /// [token] is optional and only needed from the edit profile screen: with it
  /// the backend ignores the caller's own row, so a user's current handle is
  /// not reported back to them as taken.
  Future<AvailabilityResult> checkUsernameAvailable(
    String username, {
    String? token,
  }) async {
    final response = await _apiClient.get(
      '${ApiConstants.userUsernameAvailable}'
      '?username=${Uri.encodeQueryComponent(username)}',
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Could not check username');
    }
    return AvailabilityResult(
      available: data['available'] == true,
      reason: data['reason'] as String?,
    );
  }

  /// Sign-up step 1: hand over the phone number and password. No account
  /// exists until [registerComplete] succeeds.
  Future<SignupStart> registerInitiate(
    String identifier,
    String password,
    String confirmPassword,
  ) async {
    final response = await _apiClient.post(ApiConstants.userRegisterInitiate, {
      'identifier': identifier,
      'password': password,
      'confirm_password': confirmPassword,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(_detail(data) ?? 'Could not start sign-up');
    }
    return SignupStart(
      identifier: data['identifier'] as String,
      otpSent: data['otp_sent'] == true,
    );
  }

  /// Resends the sign-up verification code by SMS.
  Future<void> registerResendOtp(String identifier) async {
    final response = await _apiClient.post(ApiConstants.userRegisterResendOtp, {
      'identifier': identifier,
    });
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(_detail(data) ?? 'Failed to resend OTP');
    }
  }

  /// Sign-up step 2 (phone): exchange the SMS code for the sign-up token.
  Future<String> registerVerifyPhone(
    String identifier,
    String otpCode,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.userRegisterVerifyPhone,
      {'identifier': identifier, 'otp_code': otpCode},
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(_detail(data) ?? 'Phone verification failed');
    }
    return data['signup_token'] as String;
  }

  /// Sign-up step 3: create the account and log in. The profile photo is
  /// uploaded separately with [updatePhoto] using the returned session token.
  Future<AuthResponse> registerComplete(
    String signupToken,
    String username,
    String displayName,
  ) async {
    final response = await _apiClient.post(ApiConstants.userRegisterComplete, {
      'signup_token': signupToken,
      'username': username,
      'display_name': displayName,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(_detail(data) ?? 'Registration failed');
    }
    return AuthResponse.fromJson(data);
  }

  /// Login step 1: the password is checked and an OTP is texted to the number
  /// on the account. Returns that number, which [loginVerify] needs.
  Future<String> loginInitiate(String identifier, String password) async {
    final response = await _apiClient.post(ApiConstants.userLoginInitiate, {
      'identifier': identifier,
      'password': password,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(_detail(data) ?? 'Login failed');
    }
    return data['phone'] as String;
  }

  /// Signs in with a Firebase ID token obtained from Google Sign-In. The
  /// backend finds-or-creates the account and returns the same session shape
  /// as every other login path.
  Future<GoogleAuthResult> signInWithGoogle(String idToken) async {
    final response = await _apiClient.post(ApiConstants.userAuthGoogle, {
      'id_token': idToken,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(_detail(data) ?? 'Google sign-in failed');
    }
    return GoogleAuthResult(
      auth: AuthResponse.fromJson(data),
      profileComplete: data['profile_complete'] == true,
    );
  }

  /// FastAPI reports validation errors as a list of objects rather than a
  /// string, so pull out the first message instead of showing raw JSON.
  String? _detail(dynamic data) {
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] is String) {
        return (first['msg'] as String).replaceFirst('Value error, ', '');
      }
    }
    return null;
  }

  Future<AuthResponse> loginVerify(
    String phone,
    String password,
    String otpCode,
  ) async {
    final response = await _apiClient.post(ApiConstants.userLoginVerify, {
      'phone': phone,
      'password': password,
      'otp_code': otpCode,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Login failed');
    }
    return AuthResponse.fromJson(data);
  }

  /// Starts a password reset by texting a code to the registered number.
  Future<void> forgotPasswordRequestOtp(String identifier) async {
    final response = await _apiClient.post(
      ApiConstants.userForgotPasswordRequestOtp,
      {'identifier': identifier},
    );
    if (response.statusCode != 200) {
      throw Exception(_detail(jsonDecode(response.body)) ?? 'Failed to send OTP');
    }
  }

  Future<void> forgotPasswordVerifyOtp(String identifier, String otpCode) async {
    final response = await _apiClient.post(
      ApiConstants.userForgotPasswordVerifyOtp,
      {'identifier': identifier, 'otp_code': otpCode},
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(_detail(data) ?? 'OTP verification failed');
    }
  }

  /// Finishes the reset with the OTP texted to the registered number.
  Future<void> forgotPasswordReset(
    String identifier,
    String newPassword, {
    String? otpCode,
  }) async {
    final response = await _apiClient.post(ApiConstants.userForgotPasswordReset, {
      'identifier': identifier,
      'otp_code': otpCode,
      'new_password': newPassword,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(_detail(data) ?? 'Failed to reset password');
    }
  }

  Future<void> logout(String token) async {
    final response = await _apiClient.post(
      ApiConstants.userLogout,
      {},
      token: token,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Logout failed');
    }
  }

  /// Asks the admins to delete this account. Nothing is removed right away:
  /// the request lands in the admin panel's notification feed and an admin
  /// carries out the deletion from there.
  Future<void> requestAccountDeletion(String token, {String? reason}) async {
    final response = await _apiClient.post(
      ApiConstants.userDeleteAccount,
      {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
      token: token,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(_detail(data) ?? 'Failed to request account deletion');
    }
  }

  Future<void> changePassword(
    String token,
    String currentPassword,
    String newPassword,
  ) async {
    final response = await _apiClient.post(ApiConstants.userChangePassword, {
      'current_password': currentPassword,
      'new_password': newPassword,
    }, token: token);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to change password');
    }
  }

  Future<bool> checkSessionActive(String token) async {
    final response = await _apiClient.get(
      ApiConstants.userSessionCheck,
      token: token,
    );
    return response.statusCode == 200;
  }

  Future<List<Map<String, dynamic>>> getListeners(
    String token, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = UserDataCache().cachedListeners;
      if (cached != null) return cached;
    }
    final response = await _apiClient.get(
      ApiConstants.userListeners,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load listeners');
    }
    final listeners = List<Map<String, dynamic>>.from(data);
    UserDataCache().setListeners(listeners);
    return listeners;
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
    // The listener is now someone the user has called, which changes where
    // their card sits on the home screen. Drop the cached catalogue so the
    // next read refetches with the updated `last_interacted_at`.
    UserDataCache().invalidateListeners();
    return data;
  }

  /// Polling fallback while ringing: returns the call status and, once the
  /// listener has joined, the caller's LiveKit token and url.
  Future<Map<String, dynamic>> getCallStatus(String token, int callId) async {
    final response = await _apiClient.get(
      ApiConstants.callStatus(callId),
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load call status');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> startRecording(String token, int callId) async {
    final response = await _apiClient.post(
      ApiConstants.callRecordingStart(callId),
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
      ApiConstants.callCancel(callId),
      {},
      token: token,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to cancel call');
    }
  }

  Future<void> timeoutCall(String token, int callId) async {
    final response = await _apiClient.post(
      ApiConstants.callTimeout(callId),
      {},
      token: token,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to mark call as missed');
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

  Future<void> reportCoinExceeded(String token, int callId) async {
    final response = await _apiClient.post(
      ApiConstants.callCoinExceeded(callId),
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
    final response = await _apiClient.post(ApiConstants.userFcmToken, {
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
      if (response.statusCode == 402) {
        throw InsufficientCoinsException(data['detail']);
      }
      throw Exception(data['detail'] ?? 'Failed to send message');
    }
    UserDataCache().invalidateMe();
    UserDataCache().invalidateThreads();
    return data;
  }
Future<Map<String, dynamic>> updatePhoto(String token, String filePath) async {
    final response = await _apiClient.postMultipart(
      ApiConstants.userPhoto,
      {},
      filePath,
      'file',
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to update photo');
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
      if (response.statusCode == 402) {
        throw InsufficientCoinsException(data['detail']);
      }
      throw Exception(data['detail'] ?? 'Failed to send voice message');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> getChatMessages(
    String token,
    int listenerId, {
    int? beforeId,
  }) async {
    var path = ApiConstants.userMessages(listenerId);
    if (beforeId != null) path = '$path?before_id=$beforeId';
    final response = await _apiClient.get(
      path,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load messages');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> markMessagesDelivered(String token, List<int> messageIds) async {
    await _apiClient.post(
      ApiConstants.userMarkDelivered,
      {'message_ids': messageIds},
      token: token,
    );
  }

  Future<void> markMessagesRead(String token, int listenerId) async {
    await _apiClient.post(
      ApiConstants.userMarkRead(listenerId),
      {},
      token: token,
    );
  }

  Future<List<Map<String, dynamic>>> getChatThreads(
    String token, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = UserDataCache().cachedThreads;
      if (cached != null) return cached;
    }
    final response = await _apiClient.get(
      ApiConstants.userChatThreads,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load threads');
    }
    final threads = List<Map<String, dynamic>>.from(data);
    UserDataCache().setThreads(threads);
    return threads;
  }

  /// One page of call logs, newest first. [beforeId] is the id of the oldest
  /// row already held, so the server only sends what is missing.
  Future<List<Map<String, dynamic>>> getCallHistory(
    String token, {
    int? beforeId,
    int limit = 25,
  }) async {
    var path = '${ApiConstants.userCallHistory}?limit=$limit';
    if (beforeId != null) path = '$path&before_id=$beforeId';
    final response = await _apiClient.get(
      path,
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
      ApiConstants.deleteMessage(messageId),
      token: token,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to delete message');
    }
  }

  /// Applies a favorite/archive/mute toggle. When the device is offline the
  /// change is queued in [LocalStorage] instead of failing, so the person can
  /// keep toggling chats with no connection; [flushPendingChatSettings]
  /// (called on reconnect) pushes the queued changes to the server.
  Future<void> updateChatSettings(
    String token,
    int otherId, {
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
  }) async {
    try {
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
      await LocalStorage().clearPendingChatSettings('user', otherId);
      UserDataCache().invalidateThreads();
    } on ServerUnreachableException {
      await LocalStorage().queuePendingChatSettings(
        'user',
        otherId,
        isPinned: isPinned,
        isArchived: isArchived,
        isMuted: isMuted,
      );
    }
  }

  /// Pushes any favorite/archive/mute toggles made while offline. Safe to
  /// call whenever connectivity may have just returned (socket reconnect,
  /// app resume, chat list load) - a clean queue is a fast no-op.
  Future<void> flushPendingChatSettings(String token) async {
    final pending = await LocalStorage().getPendingChatSettings();
    final entries = pending.entries.where((e) => e.key.startsWith('user:'));
    for (final entry in entries) {
      final otherId = entry.value['other_id'] as int?;
      if (otherId == null) continue;
      try {
        final response = await _apiClient.post(ApiConstants.userChatSettings, {
          'other_id': otherId,
          'is_pinned': entry.value['is_pinned'],
          'is_archived': entry.value['is_archived'],
          'is_muted': entry.value['is_muted'],
        }, token: token);
        if (response.statusCode != 200) continue;
        await LocalStorage().clearPendingChatSettings('user', otherId);
      } on ServerUnreachableException {
        // Still offline - leave it queued and try again next time.
        break;
      } catch (_) {
        // Non-connectivity failure (e.g. thread no longer exists); drop it
        // so it doesn't retry forever.
        await LocalStorage().clearPendingChatSettings('user', otherId);
      }
    }
    if (pending.isNotEmpty) UserDataCache().invalidateThreads();
  }

  Future<Map<String, dynamic>> getMe(
    String token, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = UserDataCache().cachedMe;
      if (cached != null) return cached;
    }
    final response = await _apiClient.get(ApiConstants.userMe, token: token);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load profile');
    }
    UserDataCache().setMe(data);
    return data;
  }

  Future<Map<String, dynamic>> getListenerProfile(
    String token,
    int listenerId,
  ) async {
    final response = await _apiClient.get(
      ApiConstants.userListenerProfile(listenerId),
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load listener profile');
    }
    return data;
  }

  Future<void> updateBio(String token, String bio) async {
    final response = await _apiClient.post(ApiConstants.userBio, {
      'bio': bio,
    }, token: token);
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to update bio');
    }
    UserDataCache().invalidateMe();
  }

  /// Saves the freely editable profile fields. Only the arguments that are
  /// non-null are sent, so an unchanged field is never touched by the server.
  /// Returns the profile as it now stands, including the refreshed cool-downs.
  Future<Map<String, dynamic>> updateProfile(
    String token, {
    String? displayName,
    String? username,
    String? bio,
  }) async {
    final response = await _apiClient.post(ApiConstants.userProfile, {
      if (displayName != null) 'display_name': displayName,
      if (username != null) 'username': username,
      if (bio != null) 'bio': bio,
    }, token: token);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(_detail(data) ?? 'Failed to save your profile');
    }
    UserDataCache().invalidateMe();
    return Map<String, dynamic>.from(data);
  }

  /// Step 1 of changing the registered phone number: texts an OTP to it.
  Future<void> requestContactChangeOtp(String token, String identifier) async {
    final response = await _apiClient.post(ApiConstants.userContactRequestOtp, {
      'identifier': identifier,
    }, token: token);
    if (response.statusCode != 200) {
      throw Exception(
        _detail(jsonDecode(response.body)) ??
            'Could not send the verification code',
      );
    }
  }

  /// Step 2: prove the new phone number is reachable and save it on the
  /// account, using the OTP sent to it.
  Future<Map<String, dynamic>> verifyContactChange(
    String token,
    String identifier, {
    String? otpCode,
  }) async {
    final response = await _apiClient.post(ApiConstants.userContactVerify, {
      'identifier': identifier,
      'otp_code': otpCode,
    }, token: token);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(_detail(data) ?? 'Verification failed');
    }
    UserDataCache().invalidateMe();
    return Map<String, dynamic>.from(data);
  }

  Future<void> updateVideoCallSetting(String token, bool enabled) async {
    final response = await _apiClient.post(ApiConstants.userVideoCallSetting, {
      'enabled': enabled,
    }, token: token);
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to update video call setting');
    }
    UserDataCache().invalidateMe();
  }

  /// Digits-only WhatsApp number of the admin who handles listener enrollment,
  /// taken from the phone saved on the admin profile. Null when no admin has
  /// saved one yet, in which case the app cannot open a chat.
  Future<String?> getEnrollWhatsappNumber() async {
    final response = await _apiClient.get(ApiConstants.appEnrollContact);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    final number = data['whatsapp_number'] as String?;
    if (number == null || number.trim().isEmpty) return null;
    return number.trim();
  }
}
