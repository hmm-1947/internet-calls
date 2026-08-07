// Removed: intercepting FCM natively here conflicted with the firebase_messaging
// Flutter plugin's own registered FirebaseMessagingService, since Android only
// delivers FCM to a single declared service per app. Ringtone playback is
// triggered via MethodChannel from Dart (CallkitService) instead, calling
// into RingtoneService directly.
