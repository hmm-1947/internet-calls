import 'package:flutter/material.dart';
import 'package:livekitlistener/screens/chat/chat_list_screen.dart';
import 'package:livekitlistener/services/websocket_service.dart';

class ChatTab extends StatelessWidget {
  final WebSocketService wsService;
  const ChatTab({super.key, required this.wsService});

  @override
  Widget build(BuildContext context) {
    return ChatListScreen(wsService: wsService);
  }
}
