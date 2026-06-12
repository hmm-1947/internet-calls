import 'package:flutter/material.dart';
import 'package:livekitlistener/models/conversation.dart';
import 'package:livekitlistener/services/chat_service.dart';
import 'package:livekitlistener/services/websocket_service.dart';

import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  final WebSocketService wsService;
  const ChatListScreen({super.key, required this.wsService});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late Future<List<Conversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = ChatService.getChats();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ChatService.getChats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Conversation>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final chats = snapshot.data ?? [];

          if (chats.isEmpty) {
            return const Center(child: Text('No chats'));
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(chat.partner),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        conversationId: chat.id,
                        partnerName: chat.partner,
                        wsService: widget.wsService,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
