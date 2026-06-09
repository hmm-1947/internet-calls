//listeners fcm_service.dart
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/storage.dart';

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String _channelId = 'incoming_calls';
const String _channelName = 'Incoming Calls';
const int _callNotificationId = 999;
const int _videoCallNotificationId = 998;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final type = message.data["type"];
  final caller = message.data["caller"] ?? "Unknown";
  final sdp = message.data["sdp"];

  if (type == "incoming_video_call" && sdp != null) {
    await AppStorage.savePendingVideoCaller(caller);
    await AppStorage.savePendingVideoSdp(sdp);
    await AppStorage.savePendingVideoCallAccepted(false);
    await AppStorage.savePendingVideoCallTime();
  }
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: null,
  );
  await plugin.resolvePlatformSpecificImplementation;
  AndroidFlutterLocalNotificationsPlugin()?.createNotificationChannel(
    const AndroidNotificationChannel(
      'incoming_calls',
      'Incoming Calls',
      importance: Importance.max,
    ),
  );

  if (type == "incoming_call" || type == "incoming_video_call") {
    await plugin.show(
      id: type == "incoming_video_call" ? 998 : 999,
      title: type == "incoming_video_call"
          ? "Incoming Video Call"
          : "Incoming Call",
      body: caller,
      payload: "${type == "incoming_video_call" ? "video:" : ""}$caller",
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'incoming_calls',
          'Incoming Calls',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          autoCancel: false,
          ongoing: true,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  final payload = response.payload ?? "";
  final isVideo = payload.startsWith("video:");
  final caller = isVideo
      ? payload.substring(6)
      : (payload.isEmpty ? "Unknown" : payload);

  if (isVideo) {
    await AppStorage.savePendingVideoCallAccepted(true);
    await AppStorage.savePendingVideoCaller(caller);
  } else {
    if (response.actionId == "accept") {
      await AppStorage.savePendingCallAccepted(true);
      await AppStorage.savePendingCaller(caller);
    }
  }
}

class FCMService {
  static Future<void> initialize() async {
    await _initializeNotifications();

    FirebaseMessaging.onMessage.listen((message) async {
      final type = message.data["type"];
      final caller = message.data["caller"] ?? "Unknown";

      if (type == "incoming_call") {
        await AppStorage.savePendingCaller(caller);
        await _showIncomingCallNotification(caller);
      } else if (type == "incoming_video_call") {
        await AppStorage.savePendingVideoCaller(caller);
        if (message.data["sdp"] != null) {
          await AppStorage.savePendingVideoSdp(message.data["sdp"]);
        }
        await AppStorage.savePendingVideoCallTime();
        await _showIncomingVideoCallNotification(caller);
      }
    });
  }

  static Future<void> cancelVideoCallNotification() async {
    await _notificationsPlugin.cancel(id: _videoCallNotificationId);
  }

  static Future<void> cancelCallNotification() async {
    await _notificationsPlugin.cancel(id: _callNotificationId);
  }

  static Future<String?> getToken() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return null;
    }

    await FirebaseMessaging.instance.requestPermission();

    await FirebaseMessaging.instance.deleteToken();

    final token = await FirebaseMessaging.instance.getToken();

    print("FCM TOKEN: $token");

    return token;
  }
}

Future<void> _initializeNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const settings = InitializationSettings(android: androidSettings);

  await _notificationsPlugin.initialize(
    settings: settings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      final payload = response.payload ?? "";
      final isVideo = payload.startsWith("video:");
      final caller = isVideo ? payload.substring(6) : payload;

      if (isVideo) {
        await AppStorage.savePendingVideoCallAccepted(true);
        await AppStorage.savePendingVideoCaller(caller);
      } else {
        if (response.actionId == "accept") {
          await AppStorage.savePendingCallAccepted(true);
          await AppStorage.savePendingCaller(caller);
        }
      }

      await _notificationsPlugin.cancel(
        id: isVideo ? _videoCallNotificationId : _callNotificationId,
      );
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
}

Future<void> _showIncomingCallNotification(String caller) async {
  final androidPlugin = _notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.max,
      playSound: true,
      enableLights: true,
      enableVibration: true,
    ),
  );

  await _notificationsPlugin.show(
    id: _callNotificationId,
    title: "Incoming Call",
    body: caller,
    payload: caller,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        autoCancel: false,
        ongoing: true,
        showWhen: false,
        visibility: NotificationVisibility.public,
        actions: [
          AndroidNotificationAction(
            'accept',
            'Accept',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'decline',
            'Decline',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
    ),
  );
}

Future<void> _showIncomingVideoCallNotification(String caller) async {
  final androidPlugin = _notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.max,
      playSound: true,
      enableLights: true,
      enableVibration: true,
    ),
  );

  await _notificationsPlugin.show(
    id: _videoCallNotificationId,
    title: "Incoming Video Call",
    body: caller,
    payload: "video:$caller",
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        autoCancel: false,
        ongoing: true,
        showWhen: false,
        visibility: NotificationVisibility.public,
        actions: [
          AndroidNotificationAction(
            'accept',
            'Accept',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'decline',
            'Decline',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
    ),
  );
}
