import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/config.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();

  factory WebSocketService() => _instance;

  WebSocketService._internal();
  WebSocketChannel? _channel;
  bool _isConnecting = false;
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _chatController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get chatEvents => _chatController.stream;

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  Future<void> connect() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  final username = prefs.getString('username');
  if (token == null || username == null) return;

  _channel = WebSocketChannel.connect(
    Uri.parse('${AppConfig.wsBaseUrl}/ws/$username?token=$token'),
  );

  _channel!.stream.listen(
    (data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      _eventController.add(message);
      if (message['event'] == 'chat_message') {
        _chatController.add(message);
      }
    },
    onDone: _onDone,
    onError: _onError,
  );
}

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void _onDone() {
    _reconnect();
  }

  void _onError(dynamic error) {
    _reconnect();
  }

  Future<void> _reconnect() async {
    if (_isConnecting) return;
    _isConnecting = true;
    await Future.delayed(const Duration(seconds: 3));
    await connect();
    _isConnecting = false;
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _chatController.close();
  }
}
