import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/listener_chat_history_screen.dart';

class ListenerChatsListScreen extends StatefulWidget {
  const ListenerChatsListScreen({super.key});

  @override
  State<ListenerChatsListScreen> createState() =>
      _ListenerChatsListScreenState();
}

class _ListenerChatsListScreenState extends State<ListenerChatsListScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;
  String _chatFilter = 'all';
  String _search = '';
  StreamSubscription? _socketSub;
  String? _token;
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _token = await _localStorage.getToken();
    await _load();
    if (_token != null) {
      ChatSocketService().connect(_token!, 'listener');
      _socketSub = ChatSocketService().stream.listen(_onSocketEvent);
    }
  }

  void _onSocketEvent(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'chat_message' ||
        type == 'read_receipt' ||
        type == 'message_status') {
      _load();
    } else if (type == 'user_online' || type == 'user_offline') {
      final uid = data['user_id'];
      final idx = _threads.indexWhere((t) => t['user_id'] == uid);
      if (idx != -1) {
        setState(() {
          _threads[idx]['is_online'] = type == 'user_online';
        });
      }
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await _localStorage.getToken();
      final threads = await _repository.getChatThreads(token!);
      setState(() {
        _threads = threads;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredThreads {
    return _threads.where((t) {
      if (_chatFilter == 'archived') {
        if ((t['is_archived'] ?? false) != true) return false;
      } else {
        if ((t['is_archived'] ?? false) == true) return false;
        if (_chatFilter == 'unread' && (t['unread_count'] ?? 0) == 0)
          return false;
        if (_chatFilter == 'favorites' && (t['is_pinned'] ?? false) != true)
          return false;
      }
      if (_search.isEmpty) return true;
      return t['user_name'].toString().toLowerCase().contains(
        _search.toLowerCase(),
      );
    }).toList();
  }

  Future<void> _togglePin(Map<String, dynamic> thread) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['user_id'],
      isPinned: !(thread['is_pinned'] ?? false),
    );
    _load();
  }

  Future<void> _toggleArchive(Map<String, dynamic> thread) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['user_id'],
      isArchived: !(thread['is_archived'] ?? false),
    );
    _load();
  }

  Future<void> _toggleMute(Map<String, dynamic> thread) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['user_id'],
      isMuted: !(thread['is_muted'] ?? false),
    );
    _load();
  }

  void _showThreadOptions(Map<String, dynamic> thread) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                thread['is_pinned'] == true
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
              ),
              title: Text(thread['is_pinned'] == true ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(context);
                _togglePin(thread);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive),
              title: Text(
                thread['is_archived'] == true ? 'Unarchive' : 'Archive',
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleArchive(thread);
              },
            ),
            ListTile(
              leading: Icon(
                thread['is_muted'] == true
                    ? Icons.notifications
                    : Icons.notifications_off,
              ),
              title: Text(thread['is_muted'] == true ? 'Unmute' : 'Mute'),
              onTap: () {
                Navigator.pop(context);
                _toggleMute(thread);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0B0F1A);
    const cardColor = Color(0xFF0B0F1A);
    const pink = Color(0xFFE53950);
    const dimText = Colors.white54;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Image.asset(
          'assets/images/banner.png',
          height: 32,
          fit: BoxFit.contain,
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.more_vert, color: Colors.white70),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 4),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2032),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Search or start a new chat',
                          hintStyle: TextStyle(color: dimText),
                          prefixIcon: Icon(Icons.search, color: dimText),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _filterChip('All', _chatFilter == 'all', () {
                          setState(() => _chatFilter = 'all');
                        }, pink),
                        const SizedBox(width: 8),
                        _filterChip('Unread', _chatFilter == 'unread', () {
                          setState(() => _chatFilter = 'unread');
                        }, pink),
                        const SizedBox(width: 8),
                        _filterChip(
                          'Favorites',
                          _chatFilter == 'favorites',
                          () {
                            setState(() => _chatFilter = 'favorites');
                          },
                          pink,
                        ),
                        const SizedBox(width: 8),
                        _filterChip('Archived', _chatFilter == 'archived', () {
                          setState(() => _chatFilter = 'archived');
                        }, pink),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_filteredThreads.isEmpty)
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: const Center(
                        child: Text(
                          'No chats yet',
                          style: TextStyle(color: dimText),
                        ),
                      ),
                    )
                  else
                    ...List.generate(_filteredThreads.length, (index) {
                      final thread = _filteredThreads[index];
                      final unread = thread['unread_count'] ?? 0;
                      return Dismissible(
                        key: ValueKey(thread['user_id']),
                        background: Container(
                          color: Colors.blueGrey,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          child: const Icon(Icons.archive, color: Colors.white),
                        ),
                        secondaryBackground: Container(
                          color: Colors.blueGrey,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.archive, color: Colors.white),
                        ),
                        confirmDismiss: (_) async {
                          await _toggleArchive(thread);
                          return false;
                        },
                        child: Material(
                          color: cardColor,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            leading: Stack(
                              children: [
                                const CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Color(0xFF2A3145),
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white54,
                                  ),
                                ),
                                if (thread['is_online'] == true)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: bg, width: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Row(
                              children: [
                                if (thread['is_pinned'] == true)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.push_pin,
                                      size: 14,
                                      color: dimText,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    thread['user_name'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (thread['is_muted'] == true)
                                  const Icon(
                                    Icons.notifications_off,
                                    size: 16,
                                    color: dimText,
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              thread['last_message'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: dimText),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _fmtTime(thread['last_message_at']),
                                  style: const TextStyle(
                                    color: dimText,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (unread > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: pink,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 20,
                                      minHeight: 20,
                                    ),
                                    child: Text(
                                      '$unread',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ListenerChatHistoryScreen(
                                    userId: thread['user_id'],
                                    userName: thread['user_name'],
                                  ),
                                ),
                              );
                              _load();
                            },
                            onLongPress: () => _showThreadOptions(thread),
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }

  Widget _filterChip(
    String label,
    bool selected,
    VoidCallback onTap,
    Color pink,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? pink : const Color(0xFF1A2032),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  String _fmtTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}
