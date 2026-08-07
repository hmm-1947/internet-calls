import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/chat_thread_subtitle.dart';
import 'package:livekitapp/common/widgets/presence_dot.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/presence_cache.dart';
import 'package:livekitapp/core/network/typing_cache.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';
import 'package:livekitapp/common/utils/data_diff.dart';
import 'package:livekitapp/listener/screens/chats/listener_chat_history_screen.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';

const _bg = Color(0xFF0B0F1A);
const _pink = Color(0xFFE53950);
const _dimText = Colors.white54;

class ListenerChatsListScreen extends StatefulWidget {
  const ListenerChatsListScreen({super.key});

  @override
  State<ListenerChatsListScreen> createState() =>
      _ListenerChatsListScreenState();
}

class _ListenerChatsListScreenState extends State<ListenerChatsListScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  List<Map<String, dynamic>> _threads = ListenerDataCache().lastThreads ?? [];

  late List<Map<String, dynamic>> _filtered = _applyFilter();

  late bool _loading = _threads.isEmpty;
  bool _refreshInFlight = false;
  DateTime? _lastRefreshAt;
  String _chatFilter = 'all';
  String _search = '';
  StreamSubscription? _socketSub;
  Timer? _refreshDebounce;
  Timer? _searchDebounce;
  String? _token;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _token = await _localStorage.getToken();
    if (_token != null) {
      ChatSocketService().connect(_token!, 'listener');
      _socketSub = ChatSocketService().stream.listen(_onSocketEvent);
    }
    if (_threads.isNotEmpty) {
      _refreshSilently();
    } else {
      await _load();
    }
  }

  void _onSocketEvent(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'chat_message' ||
        type == 'read_receipt' ||
        type == 'message_status') {
      final senderId = data['user_id'];
      if (type == 'chat_message' && senderId is int) {
        TypingCache().setUserTyping(senderId, false);
      }
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(
        const Duration(milliseconds: 400),
        _refreshSilently,
      );
    } else if (type == 'typing') {
      final userId = data['user_id'];
      if (userId is! int) return;
      TypingCache().setUserTyping(userId, data['is_typing'] == true);
    } else if (type == 'socket_disconnected') {
      TypingCache().clear();
    } else if (type == 'user_online' || type == 'user_offline') {
      final userId = data['user_id'];
      if (userId is! int) return;
      final online = type == 'user_online';
      if (!online) TypingCache().setUserTyping(userId, false);
      PresenceCache().setUserOnline(userId, online);
      final index = _threads.indexWhere((t) => t['user_id'] == userId);
      if (index != -1) _threads[index]['is_online'] = online;
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _refreshDebounce?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> _applyFilter() {
    final query = _search.trim().toLowerCase();
    return _threads.where((t) {
      if (_chatFilter == 'archived') {
        if ((t['is_archived'] ?? false) != true) return false;
      } else {
        if ((t['is_archived'] ?? false) == true) return false;
        if (_chatFilter == 'unread' && (t['unread_count'] ?? 0) == 0) {
          return false;
        }
        if (_chatFilter == 'favorites' && (t['is_pinned'] ?? false) != true) {
          return false;
        }
      }
      if (query.isEmpty) return true;
      return '${t['user_name'] ?? ''}'.toLowerCase().contains(query);
    }).toList();
  }

  void _setThreads(List<Map<String, dynamic>> threads) {
    _threads = threads;
    _filtered = _applyFilter();
  }

  void _selectFilter(String filter) {
    if (_chatFilter == filter) return;
    setState(() {
      _chatFilter = filter;
      _filtered = _applyFilter();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || _search == value) return;
      setState(() {
        _search = value;
        _filtered = _applyFilter();
      });
    });
  }

  Future<void> _load() async {
    if (_refreshInFlight) return;
    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < const Duration(seconds: 5)) {
      return;
    }
    _refreshInFlight = true;
    _lastRefreshAt = now;
    final isFirstLoad = _threads.isEmpty;
    if (isFirstLoad) setState(() => _loading = true);
    try {
      final token = await _localStorage.getToken();
      if (token == null) return;
      final threads = await _repository.getChatThreads(
        token,
        forceRefresh: !isFirstLoad,
      );
      if (!mounted) return;
      if (dataChanged(_threads, threads)) {
        setState(() {
          _setThreads(threads);
          _loading = false;
        });
      } else if (_loading) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _refreshSilently() async {
    try {
      final token = await _localStorage.getToken();
      if (token == null) return;
      final threads = await _repository.getChatThreads(
        token,
        forceRefresh: true,
      );
      if (!mounted) return;
      if (!dataChanged(_threads, threads)) return;
      setState(() {
        _setThreads(threads);
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _togglePin(Map<String, dynamic> thread) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['user_id'],
      isPinned: !(thread['is_pinned'] ?? false),
    );
    _refreshSilently();
  }

  Future<void> _toggleArchive(Map<String, dynamic> thread) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['user_id'],
      isArchived: !(thread['is_archived'] ?? false),
    );
    _refreshSilently();
  }

  Future<void> _toggleMute(Map<String, dynamic> thread) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['user_id'],
      isMuted: !(thread['is_muted'] ?? false),
    );
    _refreshSilently();
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

  Future<void> _openThread(Map<String, dynamic> thread) async {
    await Navigator.of(context).push(
      slideRoute(
        ListenerChatHistoryScreen(
          userId: thread['user_id'],
          userName: '${thread['user_name'] ?? ''}',
          userPhotoUrl: thread['photo_url'],
        ),
      ),
    );
    _refreshSilently();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Container(
              height: 55,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2032),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search chats...',
                  hintStyle: TextStyle(color: _dimText),
                  prefixIcon: Icon(Icons.search, color: _dimText),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          sliver: SliverToBoxAdapter(child: _filterRow()),
                        ),
                        if (_filtered.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                'No chats yet',
                                style: TextStyle(color: _dimText),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                            sliver: SliverList.builder(
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) {
                                final thread = _filtered[index];
                                return _ThreadTile(
                                  key: ValueKey<Object?>(thread['user_id']),
                                  thread: thread,
                                  onArchive: () => _toggleArchive(thread),
                                  onOpen: () => _openThread(thread),
                                  onOptions: () => _showThreadOptions(thread),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterRow() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final entry in const {
            'all': 'All',
            'unread': 'Unread',
            'favorites': 'Favorites',
            'archived': 'Archived',
          }.entries) ...[
            _FilterChip(
              label: entry.value,
              selected: _chatFilter == entry.key,
              onTap: () => _selectFilter(entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _pink : const Color(0xFF1A2032),
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
}

class _ThreadTile extends StatelessWidget {
  final Map<String, dynamic> thread;
  final Future<void> Function() onArchive;
  final VoidCallback onOpen;
  final VoidCallback onOptions;

  const _ThreadTile({
    super.key,
    required this.thread,
    required this.onArchive,
    required this.onOpen,
    required this.onOptions,
  });

  static const _archiveBackground = ColoredBox(
    color: Colors.blueGrey,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 20),
        child: Icon(Icons.archive, color: Colors.white),
      ),
    ),
  );

  static const _archiveSecondaryBackground = ColoredBox(
    color: Colors.blueGrey,
    child: Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(right: 20),
        child: Icon(Icons.archive, color: Colors.white),
      ),
    ),
  );

  static String _fmtTime(Object? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse('$iso')?.toLocal();
    if (dt == null) return '';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = thread['unread_count'] ?? 0;
    return RepaintBoundary(
      child: Dismissible(
        key: ValueKey<Object?>(thread['user_id']),
        background: _archiveBackground,
        secondaryBackground: _archiveSecondaryBackground,
        confirmDismiss: (_) async {
          await onArchive();
          return false;
        },
        child: Material(
          color: _bg,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: Stack(
              children: [
                AvatarImage(
                  photoUrl: thread['photo_url'],
                  radius: 26,
                  iconSize: 26,
                  backgroundColor: const Color(0xFF2A3145),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: PresenceDot(
                    presence: PresenceCache().user(thread['user_id']),
                    fallback: thread['is_online'] == true,
                    borderColor: _bg,
                  ),
                ),
              ],
            ),
            title: Row(
              children: [
                if (thread['is_pinned'] == true)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.push_pin, size: 14, color: _dimText),
                  ),
                Expanded(
                  child: Text(
                    '${thread['user_name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                    color: _dimText,
                  ),
              ],
            ),
            subtitle: ChatThreadSubtitle(
              typing: TypingCache().user(thread['user_id']),
              draftKey: 'listener:${thread['user_id']}',
              lastMessage: '${thread['last_message'] ?? ''}',
              color: _dimText,
              accentColor: _pink,
              messageType: thread['last_message_type'] as String?,
              callStatus: thread['last_call_status'] as String?,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmtTime(thread['last_message_at']),
                  style: const TextStyle(color: _dimText, fontSize: 12),
                ),
                const SizedBox(height: 6),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: _pink,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Text(
                      '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
              ],
            ),
            onTap: onOpen,
            onLongPress: onOptions,
          ),
        ),
      ),
    );
  }
}
