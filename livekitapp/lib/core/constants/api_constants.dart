import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  static final String baseUrl = dotenv.env['API_BASE_URL']!;

  static const String userRegisterInitiate = '/user/register/initiate';
  static const String userRegisterVerifyOtp = '/user/register/verify-otp';
  static const String userLogin = '/user/login';
  static const String userListeners = '/user/listeners';
  static const String listenerLogin = '/listener/login';
  static const String listenerStatus = '/listener/status';
  static const String listenerLogout = '/listener/logout';
  static const String callInitiate = '/call/initiate';
  static const String userChatSend = '/chat/user/send';
  static const String listenerChatSend = '/chat/listener/send';
  static const String userChatSendVoice = '/chat/user/send-voice';
  static const String listenerChatSendVoice = '/chat/listener/send-voice';
  static const String userChatThreads = '/chat/user/threads';
  static const String listenerChatThreads = '/chat/listener/threads';
  static const String messageEdit = '/chat/message/edit';
  static const String userChatSettings = '/chat/settings';
  static const String listenerChatSettings = '/chat/listener/settings';
  static const String coinStatus = '/call';
  static const String userStatus = '/user/status';
  static const String userCallHistory = '/call/user/history';
  static String callSummary(int callId) => '/call/$callId/summary';
  static String callRate(int callId) => '/call/$callId/rate';
  static const String listenerCallHistory = '/call/listener/history';
  static const String listenerMe = '/listener/me';
  static const String listenerUsers = '/listener/users';
  static const String listenerReviews = '/call/listener/reviews';

  static String callAccept(int callId) => '/call/$callId/accept';
  static String callReady(int callId) => '/call/$callId/ready';
  static String callReject(int callId) => '/call/$callId/reject';
  static String callEnd(int callId) => '/call/$callId/end';

  static const String listenerFcmToken = '/listener/fcm-token';

  static String listenerMessages(int userId) =>
      '/chat/listener/$userId/messages';

  static String deleteMessage(int messageId) => '/chat/message/$messageId';
}
