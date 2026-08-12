import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/core/network/chat_draft_cache.dart';
import 'package:livekitapp/core/network/chat_storage.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/flavors/flavor_config.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/chats/listener_chat_history_screen.dart';
import 'package:livekitapp/listener/screens/listener_login_screen.dart';
import 'package:livekitapp/listener/screens/listener_main_screen.dart';
import 'package:livekitapp/listener/services/callkit_service.dart';
import 'package:livekitapp/listener/screens/calls/listener_call_screen.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/services/avatar_cache.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/common/services/chat_notification_service.dart';
import 'package:livekitapp/common/services/lockscreen_service.dart';
import 'package:livekitapp/common/services/voice_message_player.dart';
import 'package:livekitapp/common/utils/chat_message_merge.dart';
import 'package:livekitapp/common/widgets/active_call_bar.dart';
import 'package:livekitapp/common/widgets/splash_screen.dart';
import 'package:livekitapp/core/network/chat_message_cache.dart';

/// Top-level function — runs in a separate isolate when the app is
/// background or killed. Must be a top-level (not a class method).
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bound before anything is awaited. The lock screen shows the call natively
  // the moment the push lands, so a decline can be tapped while this isolate is
  // still booting, and the callkit plugin drops events that arrive before an
  // engine has a listener attached. Android also rejects the call by itself
  // (CallApi) for the case where nothing here is up in time.
  if (message.data['type'] == 'call') {
    _bindBackgroundCallEvents();
  }
  await _ensureEnvLoaded();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  print('[FCM-BG] Background message received: type=${message.data["type"]}');
  await _handleMessage(message);
  await _cacheAndAckChatMessage(message);
  await _cacheAndAckChatSummary(message);
  await _applyStatusPush(message);
  // Chat pushes are data-only, so nothing is shown unless we render it here.
  await ChatNotificationService.instance.handlePush(
    message.data,
    isUserApp: false,
  );
}

/// The event listener can fire before the handler has loaded the environment,
/// so every path that needs `ApiConstants` goes through this.
Future<void> _ensureEnvLoaded() async {
  if (dotenv.isInitialized && dotenv.env.isNotEmpty) return;
  await dotenv.load(fileName: ".env");
}

bool _backgroundCallEventsBound = false;

void _bindBackgroundCallEvents() {
  if (_backgroundCallEventsBound) return;
  _backgroundCallEventsBound = true;
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
    if (event == null) return;
    int? callId;
    if (event is CallEventActionCallDecline) {
      callId = int.tryParse('${event.callKitParams.extra?['call_id'] ?? ''}');
    } else if (event is CallEventActionCallTimeout) {
      callId = int.tryParse(event.id.split('-').last);
    } else {
      return;
    }
    if (callId == null) return;
    print('[FCM-BG] Rejecting call $callId from background isolate');
    try {
      await _ensureEnvLoaded();
      final token = await LocalStorage().getToken();
      if (token != null) {
        await ListenerRepository().rejectCall(token, callId);
      }
    } catch (e) {
      print('[FCM-BG] Background reject failed: $e');
    }
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  });
}

Future<void> _cacheAndAckChatSummary(RemoteMessage message) async {
  if (message.data['type'] != 'chat_summary') return;
  final userId = int.tryParse(message.data['user_id'] ?? '');
  if (userId == null) return;
  final List<dynamic> items = jsonDecode(message.data['messages'] ?? '[]');
  final ids = <int>[];
  final cachedMessages = <Map<String, dynamic>>[];
  for (final item in items) {
    final messageId = item['id'] is int
        ? item['id'] as int
        : int.tryParse('${item['id']}');
    final local = LocalChatMessage(
      id: messageId,
      clientId: item['client_id'] ?? '',
      otherId: userId,
      senderType: message.data['sender_type'] ?? 'user',
      message: item['message'] ?? '',
      status: 'sent',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await ChatStorage().upsertMessage(userId, local);
    cachedMessages.add(local.toJson());
    if (messageId != null) ids.add(messageId);
  }
  if (cachedMessages.isNotEmpty) {
    ChatMessageCache().save(
      userId,
      mergeChatMessages(ChatMessageCache().messages(userId), cachedMessages),
    );
  }
  if (ids.isEmpty) return;
  final token = await LocalStorage().getToken();
  if (token == null) return;
  try {
    await ListenerRepository().markMessagesDelivered(token, ids);
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
  final userId = int.tryParse(message.data['user_id'] ?? '');
  final messageId = int.tryParse(message.data['id'] ?? '');
  if (userId == null) return;
  final local = LocalChatMessage(
    id: messageId,
    clientId: message.data['client_id'] ?? '',
    otherId: userId,
    senderType: message.data['sender_type'] ?? 'user',
    message: message.data['message'] ?? '',
    status: 'sent',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
  await ChatStorage().upsertMessage(userId, local);
  ChatMessageCache().save(
    userId,
    mergeChatMessages(ChatMessageCache().messages(userId), [local.toJson()]),
  );
  if (messageId == null) return;
  final token = await LocalStorage().getToken();
  if (token == null) return;
  try {
    await ListenerRepository().markMessagesDelivered(token, [messageId]);
    await ChatStorage().updateStatusByServerIds([messageId], 'delivered');
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 160 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 800;

  // Paint the splash screen the instant Flutter can draw a frame, before any
  // async startup work runs. On slow devices the init below (Firebase, FCM
  // permission prompts, cache restores) can take several seconds; without
  // this, nothing is on screen at all until it finishes.
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    ),
  );

  await dotenv.load(fileName: ".env");
  final isolateName = Isolate.current.debugName;
  print('[Callkit] main() started in isolate: $isolateName');
  if (isolateName != 'main') {
    print(
      '[Callkit] Skipping UI and runApp initialization in background isolate: $isolateName',
    );
    return;
  }

  FlavorConfig.set(AppFlavor.listener);
  LockscreenService.instance.init();
  ActiveCallManager.instance.init();
  ActiveCallManager.instance.rootNavigatorKey =
      CallkitService.instance.navigatorKey;
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
    _applyStatusPush(message);
    _cacheAndAckChatSummary(message);
    _cacheAndAckChatMessage(message);
  });
  FirebaseMessaging.onMessage.listen((message) {
    if (message.data['type'] == 'chat_message' ||
        message.data['type'] == 'chat_summary') {
      chatMessageNotifier.value++;
      // The service skips conversations that are already on screen.
      ChatNotificationService.instance.handlePush(
        message.data,
        isUserApp: false,
      );
    }
  });
  // Re-register whenever FCM rotates the token
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    _registerFcmToken();
  });

  // Deliberately not awaited: chat notifications are a nice-to-have, and
  // blocking startup on them would also block FCM token registration and the
  // callkit path if the plugin ever fails to come up.
  unawaited(_initChatNotifications());

  await AvatarCache.instance.init();
  await ChatDraftCache().restore();
  await ListenerDataCache().restore();
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
    // A call push can still be in flight right after logout (the backend
    // clears the stored token, but this one was already sent). Don't show
    // the incoming-call UI for a session that no longer exists locally.
    final authToken = await LocalStorage().getToken();
    if (authToken == null) return;
    await CallkitService.instance.showIncomingCall(message.data);
  } else if (type == 'call_cancelled') {
    await CallkitService.instance.handleCallCancelled(message.data);
  }
}

final chatMessageNotifier = ValueNotifier<int>(0);

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

/// Opens the chat named by a tapped notification instead of dropping the
/// listener on the home screen. Retries while the navigator is still being
/// built, which is the normal case for a cold start.
Future<void> flushPendingChatTarget({int attempt = 0}) async {
  final target = _pendingChatTarget;
  if (target == null) return;
  final navigator = CallkitService.instance.navigatorKey.currentState;
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
      builder: (_) => ListenerChatHistoryScreen(
        userId: target.otherId,
        userName: target.name,
        userPhotoUrl: target.photoUrl,
      ),
    ),
  );
}

class ListenerApp extends StatefulWidget {
  const ListenerApp({super.key});

  @override
  State<ListenerApp> createState() => _ListenerAppState();
}

class _ListenerAppState extends State<ListenerApp> {
  StreamSubscription? _chatSub;
  StreamSubscription? _sessionSub;
  bool _loggingOut = false;

  late final Future<String?> _initialToken = LocalStorage().getToken();

  @override
  void initState() {
    super.initState();
    CallkitService.instance.init();
    CallkitService.instance.warmup();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CallkitService.instance.flushPendingNav();
      flushPendingChatTarget();
    });
    _chatSub = ChatSocketService().stream.listen((data) {
      if (data['type'] == 'chat_message') {
        chatMessageNotifier.value++;
      } else if (data['type'] == 'force_logout') {
        _forceLogout();
      } else if (data['type'] == 'gift_received') {
        _showGiftToast(data);
      }
    });
    _sessionSub = ApiClient.sessionInvalidated.listen((_) {
      _forceLogout();
    });
  }

  void _showGiftToast(Map<String, dynamic> data) {
    final ctx =
        CallkitService.instance.navigatorKey.currentState?.overlay?.context;
    if (ctx == null) return;
    final giftName = data['gift_name'] ?? 'Gift';
    final credited = data['credited_coins'] ?? 0;
    final fromName = data['from_user_name'] ?? 'Someone';
    PillMessage.showSuccess(
      ctx,
      '$fromName sent you a $giftName · +$credited coins',
    );
  }

  Future<void> _forceLogout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    await LocalStorage().clear();
    await ChatNotificationService.instance.cancelAll();
    ChatSocketService().disconnect();
    final ctx = CallkitService.instance.navigatorKey.currentState;
    if (ctx != null) {
      ctx.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ListenerLoginScreen()),
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
          navigatorKey: CallkitService.instance.navigatorKey,
          // Lets chat screens report whether they are the visible route, which
          // is what keeps the minimized voice-note bar hidden while a chat is open.
          navigatorObservers: [voiceChatRouteObserver],
          title: 'Listener App',
          debugShowCheckedModeBanner: false,
          builder: (context, child) => ActiveCallHost(
            callScreenBuilder: (callContext, info) => ListenerCallScreen(
              key: ValueKey<int>(info.callId),
              url: info.livekitUrl ?? '',
              token: info.livekitToken ?? '',
              callId: info.callId,
              isVideo: info.isVideo,
              otherPartyName: info.otherPartyName,
              otherPartyPhotoUrl: info.otherPartyPhotoUrl,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          theme: ThemeData(
            colorSchemeSeed: Colors.deepPurple,
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF0B0F1A),
            appBarTheme: const AppBarTheme(systemOverlayStyle: _overlayStyle),
          ),
          home: FutureBuilder<String?>(
            future: _initialToken,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SplashScreen();
              }
              if (snapshot.data != null) {
                return _ListenerSessionGate(token: snapshot.data!);
              }
              return const ListenerLoginScreen();
            },
          ),
        ),
      ),
    );
  }
}

class _ListenerSessionGate extends StatefulWidget {
  final String token;
  const _ListenerSessionGate({required this.token});

  @override
  State<_ListenerSessionGate> createState() => _ListenerSessionGateState();
}

class _ListenerSessionGateState extends State<_ListenerSessionGate> {
  bool? _active;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final active = await ListenerRepository().checkSessionActive(
        widget.token,
      );
      if (!active) await LocalStorage().clear();
      if (mounted) setState(() => _active = active);
    } catch (_) {
      if (mounted) setState(() => _active = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_active == null) return const SplashScreen();
    if (_active == false) return const ListenerLoginScreen();
    return const ListenerMainScreen();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _offlineTimer?.cancel();
      _reconnectSocket();
      _checkSessionActive();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _offlineTimer?.cancel();
      _offlineTimer = Timer(const Duration(seconds: 15), () async {
        if (ActiveCallManager.instance.hasActiveCall) return;
        final activeCall = await _localStorage.getActiveCall();
        if (activeCall != null) return;
        // Only drop the socket. Users already see the listener as offline the
        // moment presence is gone, and the availability switch stays where the
        // listener left it instead of being turned off behind their back after
        // a call or any other trip through the background.
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
        final ctx = CallkitService.instance.navigatorKey.currentState;
        if (ctx == null) return;
        ctx.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ListenerLoginScreen()),
          (route) => false,
        );
      }
    } catch (_) {}
  }

  Future<void> _reconnectSocket() async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    ChatSocketService().connect(token, 'listener');
    ChatSocketService().ensureConnected();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
