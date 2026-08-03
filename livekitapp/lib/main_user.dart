import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/core/network/chat_storage.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/user_data_cache.dart';
import 'package:livekitapp/flavors/flavor_config.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/services/chat_notification_service.dart';
import 'package:livekitapp/common/services/voice_message_player.dart';
import 'package:livekitapp/common/widgets/active_call_bar.dart';
import 'package:livekitapp/common/widgets/splash_screen.dart';
import 'package:livekitapp/user/screens/calls/chat_history_screen.dart';
import 'package:livekitapp/user/screens/calls/user_call_screen.dart';
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
  // Chat pushes are data-only, so nothing is shown unless we render it here.
  await ChatNotificationService.instance.handlePush(
    message.data,
    isUserApp: true,
  );
}

Future<void> _cacheAndAckChatSummary(RemoteMessage message) async {
  if (message.data['type'] != 'chat_summary') return;
  final listenerId = int.tryParse(message.data['listener_id'] ?? '');
  if (listenerId == null) return;
  final List<dynamic> items = jsonDecode(message.data['messages'] ?? '[]');
  final ids = <int>[];
  for (final item in items) {
    final messageId = item['id'] is int
        ? item['id'] as int
        : int.tryParse('${item['id']}');
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
  // The service skips conversations that are already on screen.
  ChatNotificationService.instance.handlePush(message.data, isUserApp: true);
}

/// Tapped-notification target parked until the navigator exists (cold start).
ChatNotificationTarget? _pendingChatTarget;

Future<void> _initChatNotifications() async {
  await ChatNotificationService.instance.init(onTap: _onChatNotificationTap);
  // App launched by tapping a chat notification while it was killed.
  final target = await ChatNotificationService.instance.launchTarget();
  if (target == null) return;
  _pendingChatTarget = target;
  flushPendingChatTarget();
}

void _onChatNotificationTap(ChatNotificationTarget target) {
  _pendingChatTarget = target;
  flushPendingChatTarget();
}

/// Opens the chat named by a tapped notification instead of dropping the user
/// on the home screen. Retries while the navigator is still being built, which
/// is the normal case for a cold start.
Future<void> flushPendingChatTarget({int attempt = 0}) async {
  final target = _pendingChatTarget;
  if (target == null) return;
  final navigator = userNavigatorKey.currentState;
  if (navigator == null) {
    if (attempt >= 20) return;
    Future.delayed(
      const Duration(milliseconds: 250),
      () => flushPendingChatTarget(attempt: attempt + 1),
    );
    return;
  }
  _pendingChatTarget = null;
  final token = await LocalStorage().getToken();
  if (token == null) return;
  await ChatNotificationService.instance.cancelConversation(target.otherId);
  navigator.push(
    MaterialPageRoute(
      builder: (_) => ChatHistoryScreen(
        listenerId: target.otherId,
        listenerName: target.name,
        listenerPhotoUrl: target.photoUrl,
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  FlavorConfig.set(AppFlavor.user);
  ActiveCallManager.instance.init();
  ActiveCallManager.instance.rootNavigatorKey = userNavigatorKey;
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

  // Deliberately not awaited: chat notifications are a nice-to-have, and
  // blocking startup on them would also block FCM token registration and the
  // call path if the plugin ever fails to come up.
  unawaited(_initChatNotifications());

  await UserDataCache().restore();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      flushPendingChatTarget();
    });
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
    await ChatNotificationService.instance.cancelAll();
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

  /// Status bar / navigation bar styling used across the whole app.
  /// Light icons so the clock, wifi and battery stay readable on the dark
  /// background painted behind the status bar.
  static const _overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  @override
  Widget build(BuildContext context) {
    // AnnotatedRegion keeps this style applied for every route. Without it, any
    // screen with an AppBar overrides the status bar icon colour and can leave
    // dark icons on the dark status bar (invisible).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyle,
      child: AppLifecycleReporter(
        child: MaterialApp(
          navigatorKey: userNavigatorKey,
          // Lets chat screens report whether they are the visible route, which
          // is what keeps the minimized voice-note bar hidden while a chat is open.
          navigatorObservers: [voiceChatRouteObserver],
          title: 'Calling App',
          debugShowCheckedModeBanner: false,
          builder: (context, child) => ActiveCallHost(
            callScreenBuilder: (callContext, info) => CallScreen(
              key: ValueKey<int>(info.callId),
              callId: info.callId,
              otherPartyName: info.otherPartyName,
              otherPartyPhotoUrl: info.otherPartyPhotoUrl,
              startWithVideo: info.isVideo,
              busy: info.busy,
              listenerId: info.listenerId,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          theme: ThemeData(
            colorSchemeSeed: Colors.blue,
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF0B0B0B),
            appBarTheme: const AppBarTheme(systemOverlayStyle: _overlayStyle),
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
        if (ActiveCallManager.instance.hasActiveCall) return;
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
