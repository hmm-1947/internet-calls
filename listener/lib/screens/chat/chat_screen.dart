import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/chat_message.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/websocket_service.dart';

class ChatScreen extends StatefulWidget {
  final int conversationId;
  final String partnerName;
  final WebSocketService wsService;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.partnerName,
    required this.wsService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> messages = [];
  StreamSubscription? _chatSub;
  bool loading = true;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    _currentUsername = await AuthService.getUsername();
    await loadMessages();
    _chatSub = widget.wsService.events.listen((data) {
      if (data['event'] != 'chat_message') return;
      if (data['conversation_id'] != widget.conversationId) return;
      setState(() {
        messages.add(
          ChatMessage(
            sender: data['sender'],
            message: data['message'],
            isMe: data['sender'] == _currentUsername,
          ),
        );
      });
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> loadMessages() async {
    try {
      final data = await ChatService.getMessages(
        widget.conversationId,
        _currentUsername!,
      );
      setState(() {
        messages = data;
        loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      setState(() => loading = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() {
      messages.add(
        ChatMessage(sender: _currentUsername!, message: text, isMe: true),
      );
    });
    _scrollToBottom();
    await ChatService.sendMessage(
      conversationId: widget.conversationId,
      message: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.partnerName)),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Align(
                          alignment: msg.isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.72,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: msg.isMe
                                  ? Colors.blue[700]
                                  : Colors.grey[800],
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                                bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                              ),
                            ),
                            child: Text(
                              msg.message,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
