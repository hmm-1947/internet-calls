import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/api_endpoints.dart';
import '../../core/config.dart';
import '../../services/call_service.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  final String myUsername;
  final CallService callService;

  const ChatListScreen({
    super.key,
    required this.myUsername,
    required this.callService,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;

@override
  void initState() {
    super.initState();
    _fetchChats();
    widget.callService.addChatListener(_onIncomingMessage);
  }

  @override
  void dispose() {
    widget.callService.removeChatListener(_onIncomingMessage);
    super.dispose();
  }

  void _onIncomingMessage(String from, String content) {
    setState(() {
      final index = _chats.indexWhere((c) => c['other_user'] == from);
      if (index >= 0) {
        final chat = _chats.removeAt(index);
        chat['last_message'] = content;
        chat['last_at'] = DateTime.now().toIso8601String();
        _chats.insert(0, chat);
      } else {
        _chats.insert(0, {
          'other_user': from,
          'last_message': content,
          'last_at': DateTime.now().toIso8601String(),
        });
      }
    });
  }

Future<void> _fetchChats() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse(
        '${AppConfig.httpBase}${ApiEndpoints.chats}${widget.myUsername}',
      ));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        final chats = list.map((e) => Map<String, dynamic>.from(e)).toList();
        chats.sort((a, b) => b['last_at'].compareTo(a['last_at']));
        setState(() {
          _chats = chats;
        });
      }
    } catch (e) {
      print('fetchChats error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _formatTime(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        automaticallyImplyLeading: false,
        title: const Text(
          'Chats',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF252533)),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3B6B)),
            )
          : _chats.isEmpty
              ? const Center(
                  child: Text(
                    'No chats yet',
                    style: TextStyle(color: Color(0xFF8888AA)),
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFFFF3B6B),
                  onRefresh: _fetchChats,
                  child: ListView.separated(
                    itemCount: _chats.length,
                    separatorBuilder: (_, __) => const Divider(
                      color: Color(0xFF252533),
                      height: 1,
                      indent: 72,
                    ),
                    itemBuilder: (context, index) {
                      final chat = _chats[index];
                      return ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                myUsername: widget.myUsername,
                                otherUsername: chat['other_user'],
                                callService: widget.callService,
                              ),
                            ),
                          );
                        },
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF1E1E2A),
                          child: Text(
                            chat['other_user'][0].toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFFFF3B6B),
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        title: Text(
                          chat['other_user'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          chat['last_message'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8888AA),
                            fontSize: 13,
                          ),
                        ),
                        trailing: Text(
                          _formatTime(chat['last_at']),
                          style: const TextStyle(
                            color: Color(0xFF8888AA),
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}