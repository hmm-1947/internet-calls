import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/avatar_cache.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/listener_login_screen.dart';
import 'package:livekitapp/listener/screens/listener_edit_profile_screen.dart';
import 'package:livekitapp/listener/screens/listener_reviews_screen.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/listener/screens/chats/listener_chat_history_screen.dart';
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
  List<Map<String, dynamic>> _users = [];
  bool _loadingUsers = true;
  String _search = '';
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _profileName = '';
  String? _profilePhotoUrl;
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
    final type = data['type'];
    if (type == 'user_online' || type == 'user_offline') {
      final userId = data['user_id'];
      if (userId == null) return;
      final index = _users.indexWhere((u) => u['id'] == userId);
      if (index != -1) {
        setState(() {
          _users[index]['is_online'] = type == 'user_online';
        });
      } else if (type == 'user_online') {
        _loadUsers();
      }
    }
  }

Future<void> _loadProfile() async {
  if (_token == null) return;
  try {
    final me = await _repository.getMe(_token!);
    if (mounted) {
      setState(() {
        _profileName = me['name'] ?? '';
        _profilePhotoUrl = me['photo_url'];
      });
    }
  } catch (_) {}
}

  List<Map<String, dynamic>> get _visibleUsers {
    var list = _users.where((u) {
      if (_search.isEmpty) return true;
      final name = (u['name'] ?? '').toString().toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();
    list.sort((a, b) {
      final aOnline = a['is_online'] == true;
      final bOnline = b['is_online'] == true;
      if (aOnline == bOnline) return 0;
      return aOnline ? -1 : 1;
    });
    return list;
  }

  Future<void> _loadUsers() async {
    if (_token == null) return;
    try {
      final users = await _repository.getUsers(_token!, forceRefresh: true);
      if (mounted) {
        setState(() {
          _users = users;
          _loadingUsers = false;
        });
      }
      AvatarCache.instance.precacheAll(
        users.map((u) => ApiConstants.resolveMediaUrl(u['photo_url'] as String?)),
      );
    } catch (e) {
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
    _socketSub?.cancel();
    super.dispose();
  }

  static const bg = Color(0xFF0B0F1A);
  static const pink = Color(0xFFE53950);
  static const dimText = Colors.white54;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bg,
      body: RefreshIndicator(
        color: pink,
        backgroundColor: bg,
        onRefresh: _onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
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
            const SizedBox(height: 12),
            if (_loadingUsers)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(child: CircularProgressIndicator(color: pink)),
              )
            else if (_visibleUsers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(
                  child: Text('No users found', style: TextStyle(color: dimText)),
                ),
              )
            else
              Column(
                children: _visibleUsers
                    .map(
                      (u) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildUserTile(u),
                      ),
                    )
                    .toList(),
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
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final bool isOnline = user['is_online'] == true;
    return Container(
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
          AvatarImage(photoUrl: user['photo_url'], radius: 28, iconSize: 28),
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
                    style: const TextStyle(fontSize: 13, color: Colors.white54),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        
        ],
      ),
    );
  }
}
