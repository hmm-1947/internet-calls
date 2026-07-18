import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/core/network/chat_storage.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/flavors/flavor_config.dart';
import 'package:livekitapp/shared/widgets/splash_screen.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/auth/user_login_screen.dart';
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
  await _cacheAndAckChatMessage(message);
  await _cacheAndAckChatSummary(message);
  await _applyStatusPush(message);
}

Future<void> _cacheAndAckChatSummary(RemoteMessage message) async {
  if (message.data['type'] != 'chat_summary') return;
  final listenerId = int.tryParse(message.data['listener_id'] ?? '');
  if (listenerId == null) return;
  final List<dynamic> items = jsonDecode(message.data['messages'] ?? '[]');
  final ids = <int>[];
  for (final item in items) {
    final messageId = item['id'] is int ? item['id'] as int : int.tryParse('${item['id']}');
    await ChatStorage().upsertMessage(
      listenerId,
      LocalChatMessage(
        id: messageId,
        clientId: item['client_id'] ?? '',
        otherId: listenerId,
        senderType: message.data['sender_type'] ?? 'listener',
        message: item['message'] ?? '',
        status: 'sent',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    if (messageId != null) ids.add(messageId);
  }
  if (ids.isEmpty) return;
  final token = await LocalStorage().getToken();
  if (token == null) return;
  try {
    await UserRepository().markMessagesDelivered(token, ids);
    await ChatStorage().updateStatusByServerIds(ids, 'delivered');
  } catch (_) {}
}

Future<void> _applyStatusPush(RemoteMessage message) async {
  if (message.data['type'] != 'message_status_bulk') return;
  final ids = (message.data['ids'] ?? '')
      .split(',')
      .where((s) => s.isNotEmpty)
      .map(int.parse)
      .toList();
  final status = message.data['status'] ?? 'delivered';
  if (ids.isEmpty) return;
  await ChatStorage().updateStatusByServerIds(ids, status);
}

Future<void> _cacheAndAckChatMessage(RemoteMessage message) async {
  if (message.data['type'] != 'chat_message') return;
  final listenerId = int.tryParse(message.data['listener_id'] ?? '');
  final messageId = int.tryParse(message.data['id'] ?? '');
  if (listenerId == null) return;
  await ChatStorage().upsertMessage(
    listenerId,
    LocalChatMessage(
      id: messageId,
      clientId: message.data['client_id'] ?? '',
      otherId: listenerId,
      senderType: message.data['sender_type'] ?? 'listener',
      message: message.data['message'] ?? '',
      status: 'sent',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    ),
  );
  if (messageId == null) return;
  final token = await LocalStorage().getToken();
  if (token == null) return;
  try {
    await UserRepository().markMessagesDelivered(token, [messageId]);
    await ChatStorage().updateStatusByServerIds([messageId], 'delivered');
  } catch (_) {}
}

void _handleChatMessage(RemoteMessage message) {
  if (message.data['type'] == 'chat_message') {
    _cacheAndAckChatMessage(message);
  } else if (message.data['type'] == 'chat_summary') {
    _cacheAndAckChatSummary(message);
  } else if (message.data['type'] == 'message_status_bulk') {
    _applyStatusPush(message);
  }
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

final userNavigatorKey = GlobalKey<NavigatorState>();

class _UserAppState extends State<UserApp> {
  StreamSubscription? _chatSub;
  StreamSubscription? _sessionSub;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _chatSub = ChatSocketService().stream.listen((data) {
      if (data['type'] == 'chat_message') {
        userChatDotNotifier.value = true;
      } else if (data['type'] == 'force_logout') {
        _forceLogout();
      }
    });
    _sessionSub = ApiClient.sessionInvalidated.listen((_) {
      _forceLogout();
    });
  }

  Future<void> _forceLogout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    await LocalStorage().clear();
    ChatSocketService().disconnect();
    final ctx = userNavigatorKey.currentState;
    if (ctx != null) {
      ctx.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const UserLoginScreen()),
        (route) => false,
      );
    }
    _loggingOut = false;
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _sessionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLifecycleReporter(
      child: MaterialApp(
        navigatorKey: userNavigatorKey,
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
              return _UserSessionGate(token: snapshot.data!);
            }
            return const UserLoginScreen();
          },
        ),
      ),
    );
  }
}

class _UserSessionGate extends StatefulWidget {
  final String token;
  const _UserSessionGate({required this.token});

  @override
  State<_UserSessionGate> createState() => _UserSessionGateState();
}

class _UserSessionGateState extends State<_UserSessionGate> {
  bool? _active;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final active = await UserRepository().checkSessionActive(widget.token);
      if (!active) await LocalStorage().clear();
      if (mounted) setState(() => _active = active);
    } catch (_) {
      if (mounted) setState(() => _active = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_active == null) return const SplashScreen();
    if (_active == false) return const UserLoginScreen();
    return const UserMainScreen();
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
      _checkSessionActive();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _offlineTimer?.cancel();
      _offlineTimer = Timer(const Duration(seconds: 15), () {
        _updateStatus(false);
        ChatSocketService().disconnect();
      });
    }
  }

  Future<void> _checkSessionActive() async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    try {
      final active = await _repository.checkSessionActive(token);
      if (!active) {
        await _localStorage.clear();
        ChatSocketService().disconnect();
        final ctx = userNavigatorKey.currentState;
        if (ctx == null) return;
        ctx.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const UserLoginScreen()),
          (route) => false,
        );
      }
    } catch (_) {}
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
