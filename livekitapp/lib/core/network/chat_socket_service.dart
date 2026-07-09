import 'dart:async';
import 'dart:convert';
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

  Stream<Map<String, dynamic>> get stream {
    _controller ??= StreamController<Map<String, dynamic>>.broadcast();
    return _controller!.stream;
  }

  bool get isConnected => _connected;

  void connect(String token, String role) {
    _manuallyDisconnected = false;
    if (_channel != null && _token == token && _role == role) return;
    _token = token;
    _role = role;
    _controller ??= StreamController<Map<String, dynamic>>.broadcast();
    _open();
  }

  void _open() {
    final wsUrl = ApiConstants.baseUrl.replaceFirst('http', 'ws');
    final path = _role == 'user' ? '/chat/ws/user' : '/chat/ws/listener';
    _channel = WebSocketChannel.connect(Uri.parse('$wsUrl$path?token=$_token'));
    _connected = true;
    _channel!.stream.listen(
      (data) {
        final decoded = jsonDecode(data);
        _controller?.add(decoded);
      },
      onDone: _scheduleReconnect,
      onError: (_) => _scheduleReconnect(),
    );
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      send({'type': 'ping'});
    });
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
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_token != null) _open();
    });
  }

  void disconnect() {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connected = false;
  }
}
