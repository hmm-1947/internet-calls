import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../config/config.dart';
import '../../services/auth_service.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';

class ChatService {
  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();

    if (token == null) {
      throw Exception('Not logged in');
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Future<int> startChat(String listenerUsername) async {
    final res = await http.post(
      Uri.parse(
        '${AppConfig.baseUrl}/chats/start?listener_username=$listenerUsername',
      ),
      headers: await _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to start chat');
    }

    final data = jsonDecode(res.body);

    return data['conversation_id'];
  }

  static Future<List<Conversation>> getChats() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/chats/list'),
      headers: await _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to load chats');
    }

    final List<dynamic> data = jsonDecode(res.body);

    return data.map((e) => Conversation.fromJson(e)).toList();
  }

  static Future<List<ChatMessage>> getMessages(
    int conversationId,
    String currentUsername,
  ) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/chats/$conversationId/messages'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) throw Exception('Failed to load messages');
    final List<dynamic> data = jsonDecode(res.body);
    return data.map((e) => ChatMessage.fromJson(e, currentUsername)).toList();
  }

  static Future<void> sendMessage({
    required int conversationId,
    required String message,
  }) async {
    final res = await http.post(
      Uri.parse(
        '${AppConfig.baseUrl}/chats/send'
        '?conversation_id=$conversationId'
        '&message=${Uri.encodeComponent(message)}',
      ),
      headers: await _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to send message');
    }
  }
}
