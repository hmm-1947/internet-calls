import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/flavors/flavor_config.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/listener_login_screen.dart';
import 'package:livekitapp/listener/screens/listener_main_screen.dart';
import 'package:livekitapp/listener/services/callkit_service.dart';
import 'package:livekitapp/shared/widgets/splash_screen.dart';

/// Top-level function — runs in a separate isolate when the app is
/// background or killed. Must be a top-level (not a class method).
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  print('[FCM-BG] Background message received: type=${message.data["type"]}');
  await _handleMessage(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isolateName = Isolate.current.debugName;
  print('[Callkit] main() started in isolate: $isolateName');
  if (isolateName != 'main') {
    print(
      '[Callkit] Skipping UI and runApp initialization in background isolate: $isolateName',
    );
    return;
  }

  FlavorConfig.set(AppFlavor.listener);
  await Firebase.initializeApp();

  // Register the background handler BEFORE runApp
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Prevent FCM from showing its own heads-up notification while in foreground
  // (our callkit UI handles it instead)
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: false,
    badge: false,
    sound: false,
  );

  FirebaseMessaging.onMessage.listen((message) {
    print('[FCM-FG] Foreground message received: type=${message.data["type"]}');
    _handleMessage(message);
  });
  FirebaseMessaging.onMessage.listen((message) {
    if (message.data['type'] == 'chat_message') {
      FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      chatMessageNotifier.value++;
    }
  });
  // Re-register whenever FCM rotates the token
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    _registerFcmToken();
  });

  runApp(const ListenerApp());
  _registerFcmToken();
}

Future<void> _registerFcmToken() async {
  final localStorage = LocalStorage();
  final authToken = await localStorage.getToken();
  if (authToken == null) return;
  final fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken == null) return;
  await ListenerRepository().updateFcmToken(authToken, fcmToken);
}

Future<void> _handleMessage(RemoteMessage message) async {
  final type = message.data['type'];
  if (CallkitService.instance.isDuplicateMessage(message.messageId)) return;
  if (type == 'call') {
    await CallkitService.instance.showIncomingCall(message.data);
  } else if (type == 'call_cancelled') {
    await CallkitService.instance.handleCallCancelled(message.data);
  }
}

final chatMessageNotifier = ValueNotifier<int>(0);

class ListenerApp extends StatefulWidget {
  const ListenerApp({super.key});

  @override
  State<ListenerApp> createState() => _ListenerAppState();
}

class _ListenerAppState extends State<ListenerApp> {
  StreamSubscription? _chatSub;

  @override
  void initState() {
    super.initState();
    CallkitService.instance.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CallkitService.instance.flushPendingNav();
    });
    _chatSub = ChatSocketService().stream.listen((data) {
      if (data['type'] == 'chat_message') {
        chatMessageNotifier.value++;
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
        navigatorKey: CallkitService.instance.navigatorKey,
        title: 'Listener App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.deepPurple,
          useMaterial3: true,
        ),
        home: FutureBuilder<String?>(
          future: LocalStorage().getToken(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SplashScreen();
            }
            if (snapshot.data != null) {
              return const ListenerMainScreen();
            }
            return const ListenerLoginScreen();
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
  final _repository = ListenerRepository();
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

  Future<void> _reconnectSocket() async {
    final token = await _localStorage.getToken();
    if (token != null) ChatSocketService().connect(token, 'listener');
  }

  Future<void> _updateStatus(bool isOnline) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    try {
      await _repository.updateStatus(token, isOnline);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
