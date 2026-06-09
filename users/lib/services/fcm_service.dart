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

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp();

  if (message.data["type"] == "incoming_call") {
    final caller = message.data["caller"] ?? "Unknown";

    await _initializeNotifications();
    await _showIncomingCallNotification(caller);
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(
  NotificationResponse response,
) async {
  final caller = response.payload ?? "Unknown";

  if (response.actionId == "accept") {
    await AppStorage.savePendingCallAccepted(true);
    await AppStorage.savePendingCaller(caller);
  }
}

class FCMService {
  static Future<void> initialize() async {
    await _initializeNotifications();

    FirebaseMessaging.onMessage.listen((message) async {
      if (message.data["type"] == "incoming_call") {
        final caller = message.data["caller"] ?? "Unknown";

        await AppStorage.savePendingCaller(caller);

        await _showIncomingCallNotification(caller);
      }
    });
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
  const androidSettings = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );

  const settings = InitializationSettings(
    android: androidSettings,
  );

  await _notificationsPlugin.initialize(
    settings: settings,
    onDidReceiveNotificationResponse: (
      NotificationResponse response,
    ) async {
      final caller = response.payload ?? "Unknown";

      if (response.actionId == "accept") {
        await AppStorage.savePendingCallAccepted(true);
        await AppStorage.savePendingCaller(caller);
      }

      await _notificationsPlugin.cancel(
        id: _callNotificationId,
      );
    },
    onDidReceiveBackgroundNotificationResponse:
        notificationTapBackground,
  );
}

Future<void> _showIncomingCallNotification(
  String caller,
) async {
  final androidPlugin =
      _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

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