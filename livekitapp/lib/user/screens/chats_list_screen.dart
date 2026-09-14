import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/avatar_cache.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/chat_message_bubble.dart';
import 'package:livekitapp/common/widgets/chat_thread_subtitle.dart';
import 'package:livekitapp/common/widgets/presence_dot.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/presence_cache.dart';
import 'package:livekitapp/core/network/typing_cache.dart';
import 'package:livekitapp/core/network/user_data_cache.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/common/utils/data_diff.dart';
import 'package:livekitapp/user/screens/calls/chat_history_screen.dart';

const _bg = Color(0xFF0B0F1A);
const _pink = Color(0xFFE53950);
const _dimText = Colors.white54;

/// Time for a thread's last message, shown on the right of the chat row:
/// the clock time if it was today, `Yesterday` if it was yesterday, else a
/// short date.
String _threadTimeLabel(Object? iso) {
  if (iso == null) return '';
  final date = chatMessageTime(iso);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return clockLabel(iso);
  if (diff == 1) return 'Yesterday';
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? activeColor : const Color(0xFF1A2032),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  List<Map<String, dynamic>> _threads = UserDataCache().lastThreads ?? [];

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
    _precacheAvatars(_threads);
    _token = await _localStorage.getToken();
    if (_token != null) {
      ChatSocketService().connect(_token!, 'user');
      _socketSub = ChatSocketService().stream.listen(_onSocketEvent);
      _flushPendingChatSettings();
    }
    if (_threads.isNotEmpty) {
      _refreshSilently();
    } else {
      await _load();
    }
    _refreshProfile();
  }

  /// Pushes any favorite/archive/mute toggles made while offline. Called on
  /// load and whenever the chat socket reconnects, since either is a sign
  /// connectivity may have just returned.
  Future<void> _flushPendingChatSettings() async {
    if (_token == null) return;
    await _repository.flushPendingChatSettings(_token!);
  }

  Future<void> _refreshProfile() async {
    if (_token == null) return;
    try {
      await _repository.getMe(_token!, forceRefresh: true);
    } catch (_) {}
  }

  void _onSocketEvent(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'chat_message' ||
        type == 'read_receipt' ||
        type == 'message_status') {
      final listenerId = data['listener_id'];
      if (type == 'chat_message' && listenerId is int) {
        TypingCache().setListenerTyping(listenerId, false);
      }
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(
        const Duration(milliseconds: 400),
        _refreshSilently,
      );
    } else if (type == 'typing') {
      final listenerId = data['listener_id'];
      if (listenerId is! int) return;
      TypingCache().setListenerTyping(listenerId, data['is_typing'] == true);
    } else if (type == 'socket_disconnected') {
      TypingCache().clear();
    } else if (type == 'socket_connected') {
      _flushPendingChatSettings();
    } else if (type == 'listener_online' || type == 'listener_offline') {
      final listenerId = data['listener_id'];
      if (listenerId is! int) return;
      final online = type == 'listener_online';
      if (!online) TypingCache().setListenerTyping(listenerId, false);
      final index = _threads.indexWhere((t) => t['listener_id'] == listenerId);
      if (index != -1) _threads[index]['is_online'] = online;
    } else if (type == 'listener_presence') {
      final listenerId = data['listener_id'];
      if (listenerId is! int) return;
      PresenceCache().setListenerOnline(
        listenerId,
        data['presence_online'] == true,
      );
    } else if (type == 'coins_updated') {
      final coins = data['coins'];
      if (coins is int) UserDataCache().updateCoins(coins);
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
      return '${t['listener_name'] ?? ''}'.toLowerCase().contains(query);
    }).toList();
  }

  void _setThreads(List<Map<String, dynamic>> threads) {
    _threads = threads;
    _filtered = _applyFilter();
    _precacheAvatars(threads);
  }

  void _precacheAvatars(List<Map<String, dynamic>> threads) {
    if (threads.isEmpty) return;
    AvatarCache.instance.precacheAll(
      threads.map(
        (t) => ApiConstants.resolveMediaUrl(t['photo_url'] as String?),
      ),
    );
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

  /// Flips [field] on the given thread immediately in the UI (works with no
  /// connection), then sends the change to the server - updateChatSettings
  /// queues it locally on its own if that call fails offline.
  void _applyLocalThreadChange(Map<String, dynamic> thread, String field, bool value) {
    final index = _threads.indexWhere(
      (t) => t['listener_id'] == thread['listener_id'],
    );
    if (index == -1) return;
    setState(() {
      _threads[index][field] = value;
      _filtered = _applyFilter();
    });
  }

  Future<void> _togglePin(Map<String, dynamic> thread) async {
    final next = !(thread['is_pinned'] ?? false);
    _applyLocalThreadChange(thread, 'is_pinned', next);
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['listener_id'],
      isPinned: next,
    );
  }

  Future<void> _toggleArchive(Map<String, dynamic> thread) async {
    final next = !(thread['is_archived'] ?? false);
    _applyLocalThreadChange(thread, 'is_archived', next);
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['listener_id'],
      isArchived: next,
    );
  }

  Future<void> _toggleMute(Map<String, dynamic> thread) async {
    final next = !(thread['is_muted'] ?? false);
    _applyLocalThreadChange(thread, 'is_muted', next);
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['listener_id'],
      isMuted: next,
    );
  }

  void _showThreadOptions(Map<String, dynamic> thread) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141821),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Wrap(
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _ThreadOptionTile(
                icon: thread['is_pinned'] == true
                    ? Icons.favorite
                    : Icons.favorite_border,
                label: thread['is_pinned'] == true
                    ? 'Remove from Favorites'
                    : 'Favorites',
                onTap: () {
                  Navigator.pop(context);
                  _togglePin(thread);
                },
              ),
              _ThreadOptionTile(
                icon: Icons.archive_outlined,
                label: thread['is_archived'] == true ? 'Unarchive' : 'Archive',
                onTap: () {
                  Navigator.pop(context);
                  _toggleArchive(thread);
                },
              ),
              _ThreadOptionTile(
                icon: thread['is_muted'] == true
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
                label: thread['is_muted'] == true ? 'Unmute' : 'Mute',
                onTap: () {
                  Navigator.pop(context);
                  _toggleMute(thread);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openThread(Map<String, dynamic> thread) async {
    await Navigator.of(context).push(
      slideRoute(
        ChatHistoryScreen(
          listenerId: thread['listener_id'],
          listenerName: '${thread['listener_name'] ?? ''}',
          listenerPhotoUrl: thread['photo_url'],
          listenerBadgeTag: thread['badge_tag'] as Map<String, dynamic>?,
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
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                          sliver: SliverToBoxAdapter(child: _filterRow()),
                        ),
                        if (_chatFilter == 'group')
                          _placeholder(
                            'Coming soon .........',
                            color: _pink.withValues(alpha: 0.6),
                            bold: true,
                          )
                        else if (_filtered.isEmpty)
                          _placeholder('No chats yet')
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                            sliver: SliverList.builder(
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) {
                                final thread = _filtered[index];
                                return _ThreadTile(
                                  key: ValueKey<Object?>(thread['listener_id']),
                                  thread: thread,
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
            'group': 'Group(Beta)',
          }.entries) ...[
            _FilterChip(
              label: entry.value,
              selected: _chatFilter == entry.key,
              onTap: () => _selectFilter(entry.key),
              activeColor: _pink,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _placeholder(String message, {Color? color, bool bold = false}) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: color ?? _dimText,
            fontSize: bold ? 16 : null,
            fontWeight: bold ? FontWeight.w600 : null,
          ),
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final Map<String, dynamic> thread;
  final VoidCallback onOpen;
  final VoidCallback onOptions;

  const _ThreadTile({
    super.key,
    required this.thread,
    required this.onOpen,
    required this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    final unread = thread['unread_count'] ?? 0;
    return RepaintBoundary(
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
                    presence: PresenceCache().listener(thread['listener_id']),
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
                    '${thread['listener_name'] ?? ''}',
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
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ChatThreadSubtitle(
                typing: TypingCache().listener(thread['listener_id']),
                draftKey: 'user:${thread['listener_id']}',
                lastMessage: '${thread['last_message'] ?? ''}',
                color: unread > 0 ? Colors.white70 : _dimText,
                accentColor: _pink,
                messageType: thread['last_message_type'] as String?,
                callStatus: thread['last_call_status'] as String?,
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _threadTimeLabel(thread['last_message_at']),
                  style: const TextStyle(color: _dimText, fontSize: 12),
                ),
                const SizedBox(height: 6),
                if (unread > 0)
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: _pink,
                    child: Text(
                      '$unread',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
              ],
            ),
            onTap: onOpen,
            onLongPress: onOptions,
          ),
        ),
    );
  }
}

class _ThreadOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ThreadOptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}
