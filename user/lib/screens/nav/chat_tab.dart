import 'package:flutter/material.dart';
import 'package:livekitcalls/screens/chat/chat_list_screen.dart';
import 'package:livekitcalls/services/websocket_service.dart';

class ChatTab extends StatelessWidget {
  final WebSocketService wsService;
  const ChatTab({super.key, required this.wsService});

  @override
  Widget build(BuildContext context) {
    return ChatListScreen(wsService: wsService);
  }
}
