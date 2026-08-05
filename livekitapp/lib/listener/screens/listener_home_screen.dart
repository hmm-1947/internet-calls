import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/avatar_cache.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/user_profile_view_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class ListenerHomeScreen extends StatefulWidget {
  final Future<void> Function()? onRefresh;

  const ListenerHomeScreen({super.key, this.onRefresh});

  @override
  State<ListenerHomeScreen> createState() => _ListenerHomeScreenState();
}

class _ListenerHomeScreenState extends State<ListenerHomeScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  final _socketService = ChatSocketService();
  StreamSubscription<Map<String, dynamic>>? _socketSub;
  String? _token;
  List<Map<String, dynamic>> _users = const [];

  List<Map<String, dynamic>> _visibleUsers = const [];

  bool _loadingUsers = true;
  String _search = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _initStatus();
  }

  Future<void> _initStatus() async {
    await Permission.microphone.request();
    _token = await _localStorage.getToken();
    if (_token == null) return;
    // Connect first: the socket handshake is what publishes presence, and the
    // server already announces the listener as online when their stored
    // availability switch is on. Echoing /me back through POST /status made the
    // app overwrite that switch with whatever transient value it just read.
    _socketService.connect(_token!, 'listener');
    _socketService.ensureConnected();
    _socketSub = _socketService.stream.listen(_handleSocketEvent);
    _loadUsers();
    _loadProfile();
  }

  void _handleSocketEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type'];
    if (type != 'user_online' && type != 'user_offline') return;
    final userId = data['user_id'];
    if (userId == null) return;
    final index = _users.indexWhere((u) => u['id'] == userId);
    if (index == -1) {
      if (type == 'user_online') _loadUsers();
      return;
    }
    final online = type == 'user_online';
    if (_users[index]['is_online'] == online) return;
    setState(() {
      _users[index]['is_online'] = online;
      _recomputeVisible();
    });
  }

  Future<void> _loadProfile() async {
    if (_token == null) return;
    try {
      await _repository.getMe(_token!);
    } catch (_) {}
  }

  void _recomputeVisible() {
    final query = _search.trim().toLowerCase();
    final list = query.isEmpty
        ? List<Map<String, dynamic>>.of(_users)
        : _users
              .where((u) => '${u['name'] ?? ''}'.toLowerCase().contains(query))
              .toList();
    list.sort((a, b) {
      final aOnline = a['is_online'] == true;
      final bOnline = b['is_online'] == true;
      if (aOnline == bOnline) return 0;
      return aOnline ? -1 : 1;
    });
    _visibleUsers = list;
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || _search == value) return;
      setState(() {
        _search = value;
        _recomputeVisible();
      });
    });
  }

  Future<void> _loadUsers() async {
    if (_token == null) return;
    try {
      final users = await _repository.getUsers(_token!, forceRefresh: true);
      if (mounted) {
        setState(() {
          _users = users;
          _recomputeVisible();
          _loadingUsers = false;
        });
      }
      AvatarCache.instance.precacheAll(
        users.map(
          (u) => ApiConstants.resolveMediaUrl(u['photo_url'] as String?),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _onRefresh() async {
    _socketService.ensureConnected();
    await Future.wait([
      _loadUsers(),
      _loadProfile(),
      if (widget.onRefresh != null) widget.onRefresh!(),
    ]);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _socketSub?.cancel();
    super.dispose();
  }

  static const bg = Color(0xFF0B0F1A);
  static const pink = Color(0xFFE53950);
  static const dimText = Colors.white54;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: RefreshIndicator(
        color: pink,
        backgroundColor: bg,
        onRefresh: _onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSearchBar(),
                    const SizedBox(height: 20),
                    const Text(
                      'Users',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loadingUsers || _visibleUsers.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Center(
                    child: _loadingUsers
                        ? const CircularProgressIndicator(color: pink)
                        : const Text(
                            'No users found',
                            style: TextStyle(color: dimText),
                          ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                sliver: SliverList.separated(
                  itemCount: _visibleUsers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final user = _visibleUsers[index];
                    return RepaintBoundary(
                      key: ValueKey<Object?>(user['id']),
                      child: _buildUserTile(user),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2B3C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: dimText, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'Search users...',
                hintStyle: TextStyle(color: dimText, fontSize: 16),
                border: InputBorder.none,
                isCollapsed: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the tapped user's profile. The values already on the tile are
  /// handed over so the profile paints instantly instead of flashing empty.
  void _openUserProfile(Map<String, dynamic> user) {
    final id = user['id'];
    if (id is! int) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileViewScreen(
          userId: id,
          initialName: user['name'] as String?,
          initialPhotoUrl: user['photo_url'] as String?,
          initialIsOnline: user['is_online'] == true,
        ),
      ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final bool isOnline = user['is_online'] == true;
    return InkWell(
      onTap: () => _openUserProfile(user),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xCC1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x0DFFFFFF)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AvatarImage(
                  photoUrl: user['photo_url'],
                  radius: 28,
                  iconSize: 28,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isOnline
                          ? const Color(0xFF74D8BD)
                          : Colors.grey.shade600,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0B0F1A),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['name'] ?? 'User',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOnline ? 'Online now' : 'Offline',
                    style: TextStyle(
                      fontSize: 13,
                      color: isOnline
                          ? const Color(0xFF74D8BD)
                          : const Color(0xFFE5BDBE),
                    ),
                  ),
                  if ((user['bio'] ?? '').toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      user['bio'],
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}
