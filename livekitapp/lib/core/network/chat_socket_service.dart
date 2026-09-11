import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/core/utils/app_version.dart';

class ChatSocketService {
  static final ChatSocketService _instance = ChatSocketService._internal();
  factory ChatSocketService() => _instance;
  ChatSocketService._internal();

  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  String? _token;
  String? _role;
  bool _connected = false;
  bool _opening = false;
  bool _manuallyDisconnected = false;
  int _failedAttempts = 0;
  DateTime? _lastSessionCheck;
  static const _maxBackoffSeconds = 60;
  static const _sessionCheckThrottleSeconds = 60;

  Stream<Map<String, dynamic>> get stream {
    _controller ??= StreamController<Map<String, dynamic>>.broadcast();
    return _controller!.stream;
  }

  bool get isConnected => _connected;

  void connect(String token, String role) {
    _manuallyDisconnected = false;
    _failedAttempts = 0;
    _lastSessionCheck = null;
    if (_channel != null && _token == token && _role == role) return;
    _token = token;
    _role = role;
    _controller ??= StreamController<Map<String, dynamic>>.broadcast();
    _reconnectTimer?.cancel();
    _open();
  }

  /// Reconnects immediately instead of waiting out the current backoff delay.
  /// Called from pull-to-refresh so the app recovers as soon as the server is
  /// reachable again rather than up to a minute later.
  void ensureConnected() {
    if (_connected || _opening || _manuallyDisconnected) return;
    if (_token == null || _role == null) return;
    _reconnectTimer?.cancel();
    _failedAttempts = 0;
    _lastSessionCheck = null;
    _open();
  }

  void _open() async {
    if (_opening) return;
    _opening = true;
    final wsUrl = ApiConstants.baseUrl.replaceFirst('http', 'ws');
    final path = _role == 'user' ? '/chat/ws/user' : '/chat/ws/listener';
    // Only the listener endpoint currently gates on this (see
    // `listener_chat_ws` server-side), but it's harmless to always send it.
    final version = AppVersion.current;
    final versionParam = version != null
        ? '&app_version=${Uri.encodeQueryComponent(version)}'
        : '';
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl$path?token=$_token$versionParam'),
      );
      await _channel!.ready;
    } catch (_) {
      _channel = null;
      _opening = false;
      _failedAttempts++;
      await _verifySessionThenReconnect(_backoffSecondsFor(_failedAttempts));
      return;
    }
    _opening = false;
    _connected = true;
    _controller?.add({'type': 'socket_connected'});
    _channel!.stream.listen(
      (data) {
        _failedAttempts = 0;
        if (data is! String) return;
        Object? decoded;
        try {
          decoded = jsonDecode(data);
        } catch (_) {
          return;
        }
        if (decoded is! Map) return;
        _controller?.add(Map<String, dynamic>.from(decoded));
      },
      onDone: () {
        final code = _channel?.closeCode;
        if (code == 4003 || code == 4001) {
          _stopAndForceLogout();
          return;
        }
        if (code == 4010) {
          // app_update_required (see listener_chat_ws server-side). The
          // session is still valid — don't log out — but retrying would
          // just get closed again with the same code, so stop and let the
          // app show a blocking "update required" screen instead.
          _stopAndRequireUpdate();
          return;
        }
        _scheduleReconnect();
      },
      onError: (_) => _scheduleReconnect(),
    );
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      send({'type': 'ping'});
    });
  }

  void _stopAndForceLogout() {
    _manuallyDisconnected = true;
    _connected = false;
    _opening = false;
    _channel = null;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _controller?.add({'type': 'force_logout'});
  }

  void _stopAndRequireUpdate() {
    _manuallyDisconnected = true;
    _connected = false;
    _opening = false;
    _channel = null;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _controller?.add({'type': 'update_required'});
  }

  void send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (e) {
      // ignore: avoid_print
      print('ChatSocketService.send failed: $e');
    }
  }

  void sendTyping({int? listenerId, int? userId, required bool isTyping}) {
    if (_role == 'user') {
      send({
        'type': 'typing',
        'listener_id': listenerId,
        'is_typing': isTyping,
      });
    } else {
      send({'type': 'typing', 'user_id': userId, 'is_typing': isTyping});
    }
  }

  void _scheduleReconnect() {
    final wasConnected = _connected;
    _connected = false;
    _opening = false;
    _channel = null;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    if (wasConnected) _controller?.add({'type': 'socket_disconnected'});
    if (_manuallyDisconnected) return;
    _failedAttempts++;
    final backoffSeconds = _backoffSecondsFor(_failedAttempts);
    if (_failedAttempts >= 2) {
      _verifySessionThenReconnect(backoffSeconds);
      return;
    }
    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () {
      if (_token != null) _open();
    });
  }

  int _backoffSecondsFor(int attempt) {
    final seconds = 3 * (1 << (attempt - 1).clamp(0, 5));
    return seconds.clamp(3, _maxBackoffSeconds);
  }

  Future<void> _verifySessionThenReconnect(int backoffSeconds) async {
    final token = _token;
    final role = _role;
    if (token == null || role == null) return;
    final now = DateTime.now();
    final shouldCheckSession =
        _lastSessionCheck == null ||
        now.difference(_lastSessionCheck!).inSeconds >=
            _sessionCheckThrottleSeconds;
    if (shouldCheckSession) {
      _lastSessionCheck = now;
      try {
        final path = role == 'user'
            ? ApiConstants.userSessionCheck
            : ApiConstants.listenerSessionCheck;
        final version = AppVersion.current;
        final response = await http
            .get(
              Uri.parse('${ApiConstants.baseUrl}$path'),
              headers: {
                'Authorization': 'Bearer $token',
                if (version != null) 'X-App-Version': version,
              },
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 401) {
          _stopAndForceLogout();
          return;
        }
        if (response.statusCode == 426) {
          _stopAndRequireUpdate();
          return;
        }
      } catch (_) {
        // network error, keep retrying
      }
    }
    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () {
      if (_token != null) _open();
    });
  }

  void disconnect() {
    _manuallyDisconnected = true;
    _failedAttempts = 0;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connected = false;
    _opening = false;
  }
}
