import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  static final String baseUrl = dotenv.env['API_BASE_URL']!;

  static const String userRegisterInitiate = '/user/register/initiate';
  static const String userRegisterResendOtp = '/user/register/resend-otp';
  static const String userRegisterVerifyPhone = '/user/register/verify-phone';
  static const String userRegisterComplete = '/user/register/complete';
  static const String userUsernameAvailable = '/user/username/available';
  static const String userIdentifierAvailable = '/user/identifier/available';
  static const String userLoginInitiate = '/user/login/initiate';
  static const String userLoginVerify = '/user/login/verify';
  static const String userAuthGoogle = '/user/auth/google';
  static const String userSessionCheck = '/user/session/check';
  static const String userForgotPasswordRequestOtp =
      '/user/forgot-password/request-otp';
  static const String userForgotPasswordVerifyOtp =
      '/user/forgot-password/verify-otp';
  static const String userForgotPasswordReset = '/user/forgot-password/reset';
  static const String userLogout = '/user/logout';
  static const String userDeleteAccount = '/user/delete-account';
  static const String userChangePassword = '/user/change-password';
  static const String userListeners = '/user/listeners';
  static const String listenerLogin = '/listener/login';
  static const String listenerSessionCheck = '/listener/session/check';
  static const String listenerStatus = '/listener/status';
  static const String listenerLogout = '/listener/logout';
  static const String listenerChangePassword = '/listener/change-password';
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
  static const String listenerWallet = '/listener/wallet';
  static const String listenerWithdrawals = '/listener/withdrawals';

  static const String listenerProfile = '/listener/profile';
  static const String listenerPhoto = '/listener/photo';
  static const String listenerUsers = '/listener/users';
  static String listenerUserProfile(int userId) => '/listener/user/$userId';
  static const String listenerReviews = '/call/listener/reviews';
  static String userListenerProfile(int listenerId) =>
      '/user/listener/$listenerId';

  static String callStatus(int callId) => '/call/$callId/status';
  static String callListenerStatus(int callId) =>
      '/call/$callId/listener-status';

  static String callAccept(int callId) => '/call/$callId/accept';
  static String callReady(int callId) => '/call/$callId/ready';
  static String callReject(int callId) => '/call/$callId/reject';
  static String callEnd(int callId) => '/call/$callId/end';

  static const String listenerFcmToken = '/listener/fcm-token';

  static String listenerMessages(int userId) =>
      '/chat/listener/$userId/messages';

  static String listenerMarkRead(int userId) =>
      '/chat/listener/$userId/mark_read';

  static String deleteMessage(int messageId) => '/chat/message/$messageId';

  static String callRecordingStart(int callId) =>
      '/call/$callId/recording/start';

  static String callCancel(int callId) => '/call/$callId/cancel';

  static String callTimeout(int callId) => '/call/$callId/timeout';

  static String callCoinExceeded(int callId) => '/call/$callId/coin-exceeded';

  static const String userFcmToken = '/user/fcm-token';

  static String userMessages(int listenerId) =>
      '/chat/user/$listenerId/messages';

  static String userMarkRead(int listenerId) =>
      '/chat/user/$listenerId/mark_read';

  static const String userMarkDelivered = '/chat/user/delivered';
  static const String listenerMarkDelivered = '/chat/listener/delivered';

  static const String userMe = '/user/me';
  static const String userBio = '/user/bio';
  static const String userProfile = '/user/profile';
  static const String userContactRequestOtp = '/user/contact/request-otp';
  static const String userContactVerify = '/user/contact/verify';
  static const String userVideoCallSetting = '/user/video-call-setting';
  static const String userPhoto = '/user/photo';

  static const String giftCatalog = '/gift/catalog';
  static const String giftSend = '/gift/send';

  static const String listenerNoteSave = '/listener/notes';
  static String listenerNoteByCall(int callId) =>
      '/listener/notes/by-call/$callId';
  static String listenerNoteByUser(int userId) =>
      '/listener/notes/by-user/$userId';

  static const String billingPlans = '/billing/plans';
  static String billingPurchase(int planId) => '/billing/purchase/$planId';
  static const String billingVerifyPayment = '/billing/verify-payment';
  static const String billingPaymentFailed = '/billing/payment-failed';
  static const String billingMyPurchases = '/billing/my-purchases';

  static const String appUpgradeBanner = '/app-settings/upgrade-banner';
  static const String appEnrollContact = '/app-settings/enroll-contact';
  static const String appTermsPrivacy = '/app-settings/terms-privacy';
  static const String specialOffers = '/special-offers';

  static const String weeklyChallengeProgress = '/weekly-challenge/progress';

  static String resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }
}
