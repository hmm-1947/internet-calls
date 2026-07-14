import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/common/utils/data_diff.dart';
import 'package:livekitapp/user/screens/chat_history_screen.dart';
import 'package:livekitapp/shared/utils/fade_page_route.dart';

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
  List<Map<String, dynamic>> _threads = [];
  int _profileCoins = 0;
  bool _loading = true;
  bool _refreshInFlight = false;
  DateTime? _lastRefreshAt;
  String _chatFilter = 'all';
  String _search = '';
  StreamSubscription? _socketSub;
  Timer? _refreshDebounce;
  String? _token;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _token = await _localStorage.getToken();
    await _load();
    await _loadCoins();
    if (_token != null) {
      ChatSocketService().connect(_token!, 'user');
      _socketSub = ChatSocketService().stream.listen(_onSocketEvent);
    }
  }

  Future<void> _loadCoins() async {
    if (_token == null) return;
    final me = await _repository.getMe(_token!);
    if (mounted) setState(() => _profileCoins = me['coins'] ?? 0);
  }

  void _onSocketEvent(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'chat_message' ||
        type == 'read_receipt' ||
        type == 'message_status') {
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(
        const Duration(milliseconds: 400),
        _refreshSilently,
      );
    } else if (type == 'listener_online' || type == 'listener_offline') {
      final lid = data['listener_id'];
      final idx = _threads.indexWhere((t) => t['listener_id'] == lid);
      if (idx != -1) {
        setState(() {
          _threads[idx]['is_online'] = type == 'listener_online';
        });
      }
    } else if (type == 'coins_updated') {
      final coins = data['coins'];
      if (coins == null) return;
      setState(() => _profileCoins = coins);
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
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
      final threads = await _repository.getChatThreads(
        token!,
        forceRefresh: true,
      );
      if (dataChanged(_threads, threads)) {
        setState(() {
          _threads = threads;
          _loading = false;
        });
      } else if (_loading) {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
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
      if (mounted) setState(() => _threads = threads);
    } catch (_) {}
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
      return t['listener_name'].toString().toLowerCase().contains(
        _search.toLowerCase(),
      );
    }).toList();
  }

  Future<void> _togglePin(Map<String, dynamic> thread) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['listener_id'],
      isPinned: !(thread['is_pinned'] ?? false),
    );
    _load();
  }

  Future<void> _toggleArchive(Map<String, dynamic> thread) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['listener_id'],
      isArchived: !(thread['is_archived'] ?? false),
    );
    _load();
  }

  Future<void> _toggleMute(Map<String, dynamic> thread) async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    await _repository.updateChatSettings(
      token,
      thread['listener_id'],
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
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: const BoxDecoration(
                color: bg,
                border: Border(
                  bottom: BorderSide(color: Color(0x1AFFFFFF), width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset(
                    'assets/images/banner.png',
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.monetization_on,
                          color: Colors.amber,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$_profileCoins',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
                        children: [
                          Container(
                            height: 55,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2032),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Search or start a new chat',
                                hintStyle: TextStyle(color: dimText),
                                prefixIcon: Icon(Icons.search, color: dimText),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              onChanged: (v) => setState(() => _search = v),
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.zero,
                              children: [
                                _FilterChip(
                                  label: 'All',
                                  selected: _chatFilter == 'all',
                                  onTap: () {
                                    setState(() => _chatFilter = 'all');
                                  },
                                  activeColor: pink,
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'Unread',
                                  selected: _chatFilter == 'unread',
                                  onTap: () {
                                    setState(() => _chatFilter = 'unread');
                                  },
                                  activeColor: pink,
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'Favorites',
                                  selected: _chatFilter == 'favorites',
                                  onTap: () {
                                    setState(() => _chatFilter = 'favorites');
                                  },
                                  activeColor: pink,
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'Archived',
                                  selected: _chatFilter == 'archived',
                                  onTap: () {
                                    setState(() => _chatFilter = 'archived');
                                  },
                                  activeColor: pink,
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'Group(Beta)',
                                  selected: _chatFilter == 'group',
                                  onTap: () {
                                    setState(() => _chatFilter = 'group');
                                  },
                                  activeColor: pink,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_chatFilter == 'group')
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: Center(
                                child: Text(
                                  'Coming soon .........',
                                  style: TextStyle(
                                    color: pink.withOpacity(0.6),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          else if (_filteredThreads.isEmpty)
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
                                key: ValueKey(thread['listener_id']),
                                background: Container(
                                  color: Colors.blueGrey,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 20),
                                  child: const Icon(
                                    Icons.archive,
                                    color: Colors.white,
                                  ),
                                ),
                                secondaryBackground: Container(
                                  color: Colors.blueGrey,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: const Icon(
                                    Icons.archive,
                                    color: Colors.white,
                                  ),
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
                                                border: Border.all(
                                                  color: bg,
                                                  width: 2,
                                                ),
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
                                            thread['listener_name'],
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
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        thread['last_message'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: unread > 0
                                              ? Colors.white70
                                              : dimText,
                                        ),
                                      ),
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          thread['time_label'] ?? '',
                                          style: const TextStyle(
                                            color: dimText,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        if (unread > 0)
                                          CircleAvatar(
                                            radius: 10,
                                            backgroundColor: pink,
                                            child: Text(
                                              '$unread',
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
                                        fadeRoute(
                                          ChatHistoryScreen(
                                            listenerId: thread['listener_id'],
                                            listenerName:
                                                thread['listener_name'],
                                          ),
                                          barrierColor: bg,
                                        ),
                                      );
                                      _load();
                                    },
                                    onLongPress: () =>
                                        _showThreadOptions(thread),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
