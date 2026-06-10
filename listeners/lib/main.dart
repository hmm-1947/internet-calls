//listener main.dart
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_shell.dart';
import 'screens/auth/auth_landing.dart';
import 'services/fcm_service.dart';
import 'core/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  if (Platform.isAndroid || Platform.isIOS) {
    await Firebase.initializeApp();
    await FirebaseMessaging.instance.requestPermission();
    await FCMService.initialize();
  }

  if (Platform.isAndroid) {
    await Permission.systemAlertWindow.request();
  }

  // Check if app was launched by tapping an FCM notification
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    final type = initialMessage.data["type"];
    final caller = initialMessage.data["caller"];
    final sdp = initialMessage.data["sdp"];
    print(
      '[MAIN] launched from FCM: type=$type caller=$caller sdp=${sdp != null ? "present" : "null"}',
    );
    if (type == "incoming_video_call" && caller != null && sdp != null) {
      await AppStorage.savePendingVideoCaller(caller);
      await AppStorage.savePendingVideoSdp(sdp);
      await AppStorage.savePendingVideoCallTime();
    }
  }

  final prefs = await SharedPreferences.getInstance();
  final username = prefs.getString("username");
  final role = prefs.getString("role");

  runApp(VoiceLinkApp(savedUsername: username, savedRole: role));
}

class VoiceLinkApp extends StatelessWidget {
  final String? savedUsername;
  final String? savedRole;

  const VoiceLinkApp({super.key, this.savedUsername, this.savedRole});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2ECC71),
          surface: Color(0xFF1A1A1A),
        ),
      ),
      home: savedUsername != null
          ? MainShell(myUsername: savedUsername!, role: savedRole ?? 'user')
          : const AuthLandingScreen(),
    );
  }
}
