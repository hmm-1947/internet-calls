import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

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
  bool _manuallyDisconnected = false;
  int _failedAttempts = 0;

  Stream<Map<String, dynamic>> get stream {
    _controller ??= StreamController<Map<String, dynamic>>.broadcast();
    return _controller!.stream;
  }

  bool get isConnected => _connected;

  void connect(String token, String role) {
    _manuallyDisconnected = false;
    _failedAttempts = 0;
    if (_channel != null && _token == token && _role == role) return;
    _token = token;
    _role = role;
    _controller ??= StreamController<Map<String, dynamic>>.broadcast();
    _open();
  }

  void _open() async {
    final wsUrl = ApiConstants.baseUrl.replaceFirst('http', 'ws');
    final path = _role == 'user' ? '/chat/ws/user' : '/chat/ws/listener';
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl$path?token=$_token'),
      );
      await _channel!.ready;
    } catch (_) {
      _channel = null;
      await _verifySessionThenReconnect();
      return;
    }
    _connected = true;
    _controller?.add({'type': 'socket_connected'});
    _channel!.stream.listen(
      (data) {
        _failedAttempts = 0;
        final decoded = jsonDecode(data);
        _controller?.add(decoded);
      },
      onDone: () {
        final code = _channel?.closeCode;
        if (code == 4003 || code == 4001) {
          _stopAndForceLogout();
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
    _channel = null;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _controller?.add({'type': 'force_logout'});
  }

  void send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
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
    _connected = false;
    _channel = null;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_manuallyDisconnected) return;
    _failedAttempts++;
    if (_failedAttempts >= 2) {
      _verifySessionThenReconnect();
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_token != null) _open();
    });
  }

  Future<void> _verifySessionThenReconnect() async {
    final token = _token;
    final role = _role;
    if (token == null || role == null) return;
    try {
      final path = role == 'user'
          ? ApiConstants.userSessionCheck
          : ApiConstants.listenerSessionCheck;
      final response = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}$path'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 401) {
        _stopAndForceLogout();
        return;
      }
    } catch (_) {
      // network error, keep retrying
    }
    _failedAttempts = 0;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
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
  }
}
