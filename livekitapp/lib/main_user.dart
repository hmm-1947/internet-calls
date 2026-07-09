import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/flavors/flavor_config.dart';
import 'package:livekitapp/shared/widgets/splash_screen.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/user_home_screen.dart';
import 'package:livekitapp/user/screens/user_login_screen.dart';
import 'package:livekitapp/user/screens/user_main_screen.dart';

final userChatDotNotifier = ValueNotifier<bool>(false);

/// Background handler — must be top-level with this annotation.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

void _handleChatMessage(RemoteMessage message) {
  if (message.data['type'] != 'chat_message') return;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  FlavorConfig.set(AppFlavor.user);
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Keep FCM token up to date
  FirebaseMessaging.instance.onTokenRefresh.listen((_) => _registerFcmToken());
  FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  FirebaseMessaging.onMessage.listen(_handleChatMessage);
  runApp(const UserApp());
  _registerFcmToken();
}

Future<void> _registerFcmToken() async {
  final localStorage = LocalStorage();
  final authToken = await localStorage.getToken();
  if (authToken == null) return;
  final fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken == null) return;
  await UserRepository().updateFcmToken(authToken, fcmToken);
}

class UserApp extends StatefulWidget {
  const UserApp({super.key});

  @override
  State<UserApp> createState() => _UserAppState();
}

class _UserAppState extends State<UserApp> {
  StreamSubscription? _chatSub;

  @override
  void initState() {
    super.initState();
    _chatSub = ChatSocketService().stream.listen((data) {
      if (data['type'] == 'chat_message') {
        userChatDotNotifier.value = true;
      }
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLifecycleReporter(
      child: MaterialApp(
        title: 'Calling App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0B0B0B),
        ),
        home: FutureBuilder<String?>(
          future: LocalStorage().getToken(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SplashScreen();
            }
            if (snapshot.data != null) {
              return const UserMainScreen();
            }
            return const UserLoginScreen();
          },
        ),
      ),
    );
  }
}

class AppLifecycleReporter extends StatefulWidget {
  final Widget child;
  const AppLifecycleReporter({super.key, required this.child});

  @override
  State<AppLifecycleReporter> createState() => _AppLifecycleReporterState();
}

class _AppLifecycleReporterState extends State<AppLifecycleReporter>
    with WidgetsBindingObserver {
  final _repository = UserRepository();
  final _localStorage = LocalStorage();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _offlineTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Timer? _offlineTimer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _offlineTimer?.cancel();
      _updateStatus(true);
      _reconnectSocket();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _offlineTimer?.cancel();
      _offlineTimer = Timer(const Duration(seconds: 15), () {
        _updateStatus(false);
        ChatSocketService().disconnect();
      });
    }
  }

  Future<void> _updateStatus(bool isOnline) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    try {
      await _repository.updateStatus(token, isOnline);
    } catch (_) {}
  }

  Future<void> _reconnectSocket() async {
    final token = await _localStorage.getToken();
    if (token != null) ChatSocketService().connect(token, 'user');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
