import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/local_storage.dart' as ls;
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/core/network/presence_cache.dart';
import 'package:livekitapp/core/network/user_data_cache.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/repository/billing_repository.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/screens/calls/chat_history_screen.dart';
import 'package:livekitapp/user/screens/listener_profile_view_screen.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/user/screens/auth/user_login_screen.dart';
import 'package:livekitapp/user/screens/user_profile_screen.dart';
import 'package:livekitapp/common/utils/data_diff.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

class _AppColors {
  static const bg = Color(0xFF0B0F1A);
  static const headerBg = Color(0xCC0B0B0B);
  static const cardBg = Color(0xCC1A1A1A);
  static const cardBorder = Color(0x0DFFFFFF);
  static const inputBg = Color(0xFF1C2B3C);
  static const brandRed = Color(0xFFE11D48);
  static const online = Color(0xFF74D8BD);
  static const textSecondary = Color(0xFFD4E4FA);
  static const textMuted = Color(0xFFE5BDBE);
}

class _CoinBalanceChip extends StatelessWidget {
  final int coins;
  final bool showLabel;

  const _CoinBalanceChip({required this.coins, this.showLabel = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on, color: Colors.amber, size: 16),
          const SizedBox(width: 6),
          Text(
            showLabel ? '$coins Coins' : '$coins',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


class _DummyOfferCard extends StatelessWidget {
  final String badge;
  final String title;
  final Gradient gradient;

  const _DummyOfferCard({
    required this.badge,
    required this.title,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.fromLTRB(20, 17, 20, 20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: _AppColors.brandRed,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 10,
                    color: _AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Claim Offer',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF05141E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialOfferImageCard extends StatelessWidget {
  final String imageUrl;

  const _SpecialOfferImageCard({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isEmpty
          ? Container(color: _AppColors.cardBg)
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: _AppColors.cardBg),
            ),
    );
  }
}

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => UserHomeScreenState();
}

class UserHomeScreenState extends State<UserHomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _profileName = '';
  String? _profilePhotoUrl;
  int _profileCoins = 0;
  final _repository = UserRepository();
  final _billingRepository = BillingRepository();
  final _localStorage = LocalStorage();
  bool _loading = true;
  String? _error;
  StreamSubscription? _socketSub;
  List<Map<String, dynamic>> _listeners = [];
  int? _callingListenerId; // tracks in-flight call to prevent double-tap
  bool _videoCallEnabled = true;
  bool _videoCallDisabledByAdmin = false;

  Timer? _pollTimer;
  final PageController _offersController = PageController(
    viewportFraction: 0.92,
  );
  Timer? _offersAutoScrollTimer;
  int _offersCurrentPage = 0;
  static const int _offersCardCount = 2;
  List<Map<String, dynamic>> _specialOffers = [];

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _load();
    _initSocket();
    _pollTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) {
        _load(silent: true);
        _loadSpecialOffers();
      },
    );
    _offersAutoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_offersController.hasClients || _specialOffers.length <= 1) return;
      final current = _offersController.page?.round() ?? _offersCurrentPage;
      final next = (current + 1) % _specialOffers.length;
      _offersController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
    _loadSpecialOffers();
  }

  Future<void> _loadFromCache() async {
    final cachedListeners = await HomeCache().getJson('user_home_listeners');
    final cachedProfile = await HomeCache().getJson('user_home_profile');
    final cachedOffers = await HomeCache().getJson('user_home_offers');
    if (!mounted) return;
    setState(() {
      if (cachedListeners is List) {
        _listeners = cachedListeners.cast<Map<String, dynamic>>();
      }
      if (cachedProfile is Map) {
        _profileName = cachedProfile['name'] ?? '';
        _profilePhotoUrl = cachedProfile['photo_url'];
        _profileCoins = cachedProfile['coins'] ?? 0;
        _videoCallEnabled = cachedProfile['video_call_enabled'] ?? true;
        _videoCallDisabledByAdmin = cachedProfile['video_call_disabled_by_admin'] ?? false;
      }
      if (cachedOffers is List) {
        _specialOffers = cachedOffers.cast<Map<String, dynamic>>();
      }
      if (_listeners.isNotEmpty) _loading = false;
    });
  }

  Future<void> _loadSpecialOffers({int attempt = 0}) async {
    try {
      final offers = await _billingRepository.getSpecialOffers();
      if (!mounted) return;
      setState(() => _specialOffers = offers);
      HomeCache().setJson('user_home_offers', offers);
    } catch (_) {
      if (!mounted || attempt >= 2) return;
      final delay = Duration(seconds: 2 * (attempt + 1));
      Future.delayed(delay, () {
        if (mounted) _loadSpecialOffers(attempt: attempt + 1);
      });
    }
  }


  Future<void> _initSocket() async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    ChatSocketService().connect(token, 'user');
    _socketSub = ChatSocketService().stream.listen(_onSocketEvent);
  }

  void _onSocketEvent(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'socket_connected') {
      _load(silent: true);
      return;
    }
    if (type == 'listener_online' || type == 'listener_offline') {
      final listenerId = data['listener_id'];
      if (listenerId == null) return;
      if (listenerId is int) {
        PresenceCache().setListenerOnline(
          listenerId,
          type == 'listener_online',
        );
      }
      setState(() {
        final idx = _listeners.indexWhere((l) => l['id'] == listenerId);
        if (idx != -1) {
          _listeners[idx]['is_online'] = type == 'listener_online';
        }
      });
    } else if (type == 'listener_rating_updated') {
      final listenerId = data['listener_id'];
      if (listenerId == null) return;
      setState(() {
        final idx = _listeners.indexWhere((l) => l['id'] == listenerId);
        if (idx != -1) {
          _listeners[idx]['avg_rating'] = data['avg_rating'];
          _listeners[idx]['rating_count'] = data['rating_count'];
        }
      });
    } else if (type == 'coins_updated') {
      final coins = data['coins'];
      if (coins == null) return;
      if (coins is int) UserDataCache().updateCoins(coins);
      setState(() {
        _profileCoins = coins;
      });
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _pollTimer?.cancel();
    _offersAutoScrollTimer?.cancel();
    _offersController.dispose();
    super.dispose();
  }

  /// Silently reloads listeners and the user's own profile flags (including
  /// the video-call enabled/admin-disabled state) without showing the full
  /// loading spinner. Called by the bottom nav whenever the Home tab is
  /// (re)selected, so toggling video calls in Settings reflects immediately.
  Future<void> refresh() => _load(silent: true);

  Future<void> _pullToRefresh() async {
    ChatSocketService().ensureConnected();
    if (_socketSub == null) await _initSocket();
    await Future.wait([_load(forceRefresh: true), _loadSpecialOffers()]);
  }

  int _loadRequestId = 0;

  Future<void> _load({bool silent = false, bool forceRefresh = false}) async {
    final requestId = ++_loadRequestId;
    final isFirstLoad = _listeners.isEmpty;
    if (!silent && isFirstLoad) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final token = await _localStorage.getToken();
      final listeners = await _repository.getListeners(
        token!,
        forceRefresh: forceRefresh,
      );
      final me = await _repository.getMe(token);
      if (requestId != _loadRequestId) return;
      final newName = me['name'] ?? '';
      final newPhoto = me['photo_url'];
      final newCoins = me['coins'] ?? 0;
      final newVideoCallEnabled = me['video_call_enabled'] ?? true;
      final newVideoCallDisabledByAdmin = me['video_call_disabled_by_admin'] ?? false;
      final changed = dataChanged(_listeners, listeners) ||
          _profileName != newName ||
          _profilePhotoUrl != newPhoto ||
          _profileCoins != newCoins ||
          _videoCallEnabled != newVideoCallEnabled ||
          _videoCallDisabledByAdmin != newVideoCallDisabledByAdmin;
      if (mounted) {
        if (changed) {
          setState(() {
            _listeners = listeners;
            _profileName = newName;
            _profilePhotoUrl = newPhoto;
            _profileCoins = newCoins;
            _videoCallEnabled = newVideoCallEnabled;
            _videoCallDisabledByAdmin = newVideoCallDisabledByAdmin;
            _loading = false;
            _error = null;
          });
          HomeCache().setJson('user_home_listeners', listeners);
          HomeCache().setJson('user_home_profile', {
            'name': newName,
            'photo_url': newPhoto,
            'coins': newCoins,
            'video_call_enabled': newVideoCallEnabled,
            'video_call_disabled_by_admin': newVideoCallDisabledByAdmin,
          });
        } else if (_loading || _error != null) {
          setState(() {
            _loading = false;
            _error = null;
          });
        }
      }
    } catch (e) {
      if (requestId != _loadRequestId) return;
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }


  Future<void> _callListener(int listenerId, {bool video = false}) async {
    if (_callingListenerId != null) return;
    if (ActiveCallManager.instance.hasActiveCall) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are already on a call')),
      );
      return;
    }
    setState(() => _callingListenerId = listenerId);
    try {
      final token = await _localStorage.getToken();
      final result = await _repository.initiateCall(
        token!,
        listenerId,
        callType: video ? 'video' : 'audio',
      );
      if (!mounted) return;
      final listener = _listeners.firstWhere(
        (l) => l['id'] == listenerId,
        orElse: () => {'name': 'Listener'},
      );
      ActiveCallManager.instance.start(
        ActiveCallInfo(
          role: ActiveCallRole.user,
          callId: result['call_id'],
          otherPartyName: listener['name'] ?? 'Listener',
          otherPartyPhotoUrl: listener['photo_url'],
          isVideo: video,
          listenerId: listenerId,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _callingListenerId = null);
    }
  }

  void _openChat(Map<String, dynamic> listener) {
    Navigator.of(context).push(
      fadeRoute(
ChatHistoryScreen(
          listenerId: listener['id'],
          listenerName: listener['name'],
          listenerPhotoUrl: listener['photo_url'],
        ),
        barrierColor: _AppColors.bg,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _AppColors.bg,
      endDrawer: _buildProfileDrawer(),
      body: RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(5, 24, 5, 32 + MediaQuery.of(context).padding.bottom + 90),
          children: [
            _buildDummyOffersSection(),
            const SizedBox(height: 32),
            _buildFeaturedProfilesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileDrawer() {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A0A14), Color(0xFF0B0B0B)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _AppColors.brandRed, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _AppColors.brandRed.withOpacity(0.5),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
           child: AvatarImage(photoUrl: _profilePhotoUrl, radius: 44, iconSize: 44),
              ),
              const SizedBox(height: 12),
              Text(
                _profileName.isEmpty ? 'User' : _profileName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: _CoinBalanceChip(coins: _profileCoins, showLabel: true),
              ),

              const SizedBox(height: 28),
              ListTile(
                leading: const Icon(
                  Icons.person_outline,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Profile',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(
                    context,
                  ).push(fadeRoute(const UserProfileScreen()));
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Settings',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.white70),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  ChatSocketService().disconnect();
                  await ls.LocalStorage().clear();
                  if (!mounted) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const UserLoginScreen()),
                  );
                },
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Special Offers carousel — admin-uploaded images, falls back to dummy
  // placeholder cards when the admin hasn't uploaded any offers yet.
  // -------------------------------------------------------------------------
  Widget _buildDummyOffersSection() {
    final hasRealOffers = _specialOffers.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Special Offers',
          style: TextStyle(
            fontSize: 16,
            color: _AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: PageView(
            controller: _offersController,
            onPageChanged: (index) => setState(() => _offersCurrentPage = index),
            children: hasRealOffers
                ? _specialOffers
                    .map((offer) => _SpecialOfferImageCard(
                          imageUrl: ApiConstants.resolveMediaUrl(
                            offer['image_url'] as String?,
                          ),
                        ))
                    .toList()
                : const [
                    _DummyOfferCard(
                      badge: 'LIMITED TIME',
                      title: '50% Off First Call',
                      gradient: LinearGradient(
                        colors: [Color(0xFF1A1A1A), Color(0xFF1A1A1A)],
                      ),
                    ),
                    _DummyOfferCard(
                      badge: 'NEW',
                      title: 'Free 5-min Trial',
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_AppColors.brandRed, Color(0xFF681A19)],
                      ),
                    ),
                  ],
          ),
        ),
        if (hasRealOffers && _specialOffers.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_specialOffers.length, (index) {
              final isActive = index == _offersCurrentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive
                      ? _AppColors.brandRed
                      : _AppColors.textMuted.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Featured Profiles — REAL listener data: online status + call + chat
  // -------------------------------------------------------------------------
  Widget _buildFeaturedProfilesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Call me',
              style: TextStyle(
                fontSize: 16,
                color: _AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.refresh,
                color: _AppColors.textMuted,
                size: 20,
              ),
              onPressed: _pullToRefresh,
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null && _listeners.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                _error!,
                style: const TextStyle(color: _AppColors.textMuted),
              ),
            ),
          )
        else if (_listeners.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'No listeners available',
                style: TextStyle(color: _AppColors.textMuted),
              ),
            ),
          )
        else
          Builder(
            builder: (context) {
              final listeners = _onlineFirst(_listeners);
              return Column(
                children: [
                  for (int i = 0; i < listeners.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _buildProfileCard(listeners[i]),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }

  /// Online listeners first, offline after, keeping the server's order within
  /// each group. Done at build time so socket online/offline events reorder the
  /// list immediately without refetching.
  List<Map<String, dynamic>> _onlineFirst(List<Map<String, dynamic>> listeners) {
    return [
      ...listeners.where((l) => l['is_online'] == true),
      ...listeners.where((l) => l['is_online'] != true),
    ];
  }

  Widget _buildProfileCard(Map<String, dynamic> listener) {
    final bool isOnline = listener['is_online'] == true;
    final bool isCalling = _callingListenerId == listener['id'];
    final bool canAct = _callingListenerId == null;
    final tags = List<String>.from(listener['tags'] ?? const []);

    return GestureDetector(
      onTap: () => _openChat(listener),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _AppColors.cardBorder),
        ),
child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _openListenerProfile(listener),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AvatarImage(photoUrl: listener['photo_url'], radius: 50, iconSize: 40),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? _AppColors.online
                                : Colors.grey.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF050E17),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        listener['name'] ?? 'Listener',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${listener['age']?.toString() ?? '...'} · ${(listener['occupation'] as String?)?.isNotEmpty == true ? listener['occupation'] : '...'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            isOnline ? 'Online now' : 'Offline',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: isOnline
                                  ? _AppColors.online
                                  : _AppColors.textMuted,
                            ),
                          ),
                          if (listener['avg_rating'] != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 14),
                                const SizedBox(width: 2),
                                Text(
                                  '${listener['avg_rating']}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.amber,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: tags
                              .take(3)
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _AppColors.brandRed.withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    tag,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_videoCallEnabled) ...[
                  isCalling
                      ? const SizedBox(width: 40, height: 40)
                      : InkWell(
                          onTap: !canAct
                              ? null
                              : _videoCallDisabledByAdmin
                                  ? () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Admin has disabled video calls for your account',
                                          ),
                                        ),
                                      );
                                    }
                                  : () => _callListener(listener['id'], video: true),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _videoCallDisabledByAdmin
                                  ? _AppColors.brandRed.withOpacity(0.2)
                                  : (canAct
                                      ? _AppColors.brandRed.withOpacity(0.85)
                                      : _AppColors.brandRed.withOpacity(0.3)),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.videocam,
                              color: _videoCallDisabledByAdmin
                                  ? Colors.white38
                                  : Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                  const SizedBox(width: 6),
                ],
                isCalling
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _AppColors.brandRed,
                          ),
                        ),
                      )
                    : InkWell(
                        onTap: canAct ? () => _callListener(listener['id']) : null,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: canAct
                                ? _AppColors.brandRed
                                : _AppColors.brandRed.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openListenerProfile(Map<String, dynamic> listener) {
    Navigator.of(
      context,
    ).push(fadeRoute(ListenerProfileViewScreen(listenerId: listener['id'])));
  }
}