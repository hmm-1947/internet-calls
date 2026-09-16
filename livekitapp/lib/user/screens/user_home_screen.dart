import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/avatar_cache.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
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
import 'package:livekitapp/user/screens/user_settings_screen.dart';
import 'package:livekitapp/user/screens/upgrade_screen.dart';
import 'package:livekitapp/common/utils/data_diff.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

class _AppColors {
  static const bg = Color(0xFF0B0F1A);
  static const cardBg = Color(0xCC1A1A1A);
  static const cardBorder = Color(0x0DFFFFFF);
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

class _SpecialOfferImageCard extends StatefulWidget {
  final String imageUrl;

  const _SpecialOfferImageCard({required this.imageUrl});

  @override
  State<_SpecialOfferImageCard> createState() => _SpecialOfferImageCardState();
}

class _SpecialOfferImageCardState extends State<_SpecialOfferImageCard> {
  String? _filePath;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_SpecialOfferImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _resolve();
  }

  void _resolve() {
    _filePath = null;
    final url = widget.imageUrl;
    if (url.isEmpty) return;
    final cached = AvatarCache.instance.localPathSync(url);
    if (cached != null) {
      _filePath = cached;
      return;
    }
    AvatarCache.instance.ensureCached(url).then((path) {
      if (path == null || !mounted || widget.imageUrl != url) return;
      setState(() => _filePath = path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filePath = _filePath;
    Widget child;
    if (widget.imageUrl.isEmpty) {
      child = const ColoredBox(color: _AppColors.cardBg);
    } else if (filePath != null) {
      child = Image.file(
        File(filePath),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) =>
            const ColoredBox(color: _AppColors.cardBg),
      );
    } else {
      child = Image.network(
        widget.imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        cacheWidth:
            (MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .round(),
        errorBuilder: (context, error, stackTrace) =>
            const ColoredBox(color: _AppColors.cardBg),
      );
    }
    return Container(
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => UserHomeScreenState();
}

class UserHomeScreenState extends State<UserHomeScreen>
    with WidgetsBindingObserver {
  String _profileName = '';
  String? _profilePhotoUrl;
  int _profileCoins = 0;
  final _repository = UserRepository();
  final _billingRepository = BillingRepository();
  final _localStorage = LocalStorage();
  bool _loading = true;
  String? _error;
  StreamSubscription? _socketSub;
  List<Map<String, dynamic>> _listeners = const [];

  List<Map<String, dynamic>> _ordered = const [];

  int? _callingListenerId; // tracks in-flight call to prevent double-tap
  bool _videoCallEnabled = true;
  bool _videoCallDisabledByAdmin = false;

  Timer? _pollTimer;
  final PageController _offersController = PageController(
    viewportFraction: 0.92,
  );
  Timer? _offersAutoScrollTimer;
  final ValueNotifier<int> _offersPage = ValueNotifier<int>(0);
  List<Map<String, dynamic>> _specialOffers = const [];

  bool _visible = true;
  ValueListenable<TickerModeData>? _tickerMode;
  bool _foregrounded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFromCache();
    _load();
    _initSocket();
    _loadSpecialOffers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TickerMode.getValuesNotifier(context);
    if (identical(notifier, _tickerMode)) return;
    _tickerMode?.removeListener(_onVisibilityChanged);
    _tickerMode = notifier;
    notifier.addListener(_onVisibilityChanged);
    _onVisibilityChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foregrounded = state == AppLifecycleState.resumed;
    if (foregrounded == _foregrounded) return;
    _foregrounded = foregrounded;
    _syncTimers();
  }

  void _onVisibilityChanged() {
    final visible = _tickerMode?.value.enabled ?? true;
    if (visible == _visible) return;
    _visible = visible;
    _syncTimers();
  }

  bool get _active => _visible && _foregrounded;

  void _syncTimers() {
    if (!_active) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _offersAutoScrollTimer?.cancel();
      _offersAutoScrollTimer = null;
      return;
    }
    _pollTimer ??= Timer.periodic(const Duration(minutes: 2), (_) {
      _load(silent: true);
      _loadSpecialOffers();
    });
    _syncOffersAutoScroll();
  }

  void _syncOffersAutoScroll() {
    final wanted = _active && _specialOffers.length > 1;
    if (!wanted) {
      _offersAutoScrollTimer?.cancel();
      _offersAutoScrollTimer = null;
      return;
    }
    _offersAutoScrollTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_active) return;
      if (!_offersController.hasClients || _specialOffers.length <= 1) return;
      final current = _offersController.page?.round() ?? _offersPage.value;
      _offersController.animateToPage(
        (current + 1) % _specialOffers.length,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _loadFromCache() async {
    final cachedListeners = await HomeCache().getJson('user_home_listeners');
    final cachedProfile = await HomeCache().getJson('user_home_profile');
    final cachedOffers = await HomeCache().getJson('user_home_offers');
    if (!mounted) return;
    setState(() {
      if (cachedListeners is List) {
        _setListeners(cachedListeners.cast<Map<String, dynamic>>());
      }
      if (cachedProfile is Map) {
        _profileName = cachedProfile['name'] ?? '';
        _profilePhotoUrl = cachedProfile['photo_url'];
        _profileCoins = cachedProfile['coins'] ?? 0;
        _videoCallEnabled = cachedProfile['video_call_enabled'] ?? true;
        _videoCallDisabledByAdmin =
            cachedProfile['video_call_disabled_by_admin'] ?? false;
      }
      if (cachedOffers is List) {
        _specialOffers = cachedOffers.cast<Map<String, dynamic>>();
      }
      if (_listeners.isNotEmpty) _loading = false;
    });
    _syncOffersAutoScroll();
  }

  void _setListeners(List<Map<String, dynamic>> listeners) {
    _listeners = listeners;
    _reorder();
  }

  /// Time of the most recent call this user placed to [listener], or null when
  /// they have never called them. Mirrors `last_interacted_at` from the
  /// `/user/listeners` payload.
  static DateTime? _lastInteractedAt(Map<String, dynamic> listener) {
    final raw = listener['last_interacted_at'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  /// Orders the catalogue the same way the backend does, so a presence change
  /// pushed over the socket re-sorts the list without waiting for a refetch:
  ///
  ///  1. listeners the user has called before, online ones first
  ///  2. everyone else, online ones first
  ///
  /// Previous contacts therefore stay above strangers even while offline. A
  /// first-time user has no contacts, so this collapses to plain online-first.
  /// The sort is stable, so listeners that tie keep the server's order
  /// (most recent call first, then by id).
  void _reorder() {
    final ordered = List<Map<String, dynamic>>.of(_listeners);
    mergeSort<Map<String, dynamic>>(
      ordered,
      compare: (a, b) {
        final aInteracted = _lastInteractedAt(a) != null;
        final bInteracted = _lastInteractedAt(b) != null;
        if (aInteracted != bInteracted) return aInteracted ? -1 : 1;
        final aOnline = a['presence_online'] == true;
        final bOnline = b['presence_online'] == true;
        if (aOnline != bOnline) return aOnline ? -1 : 1;
        return 0;
      },
    );
    _ordered = ordered;
  }

  Future<void> _loadSpecialOffers({int attempt = 0}) async {
    try {
      final offers = await _billingRepository.getSpecialOffers();
      if (!mounted) return;
      if (!dataChanged(_specialOffers, offers)) return;
      setState(() => _specialOffers = offers);
      _syncOffersAutoScroll();
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
    if (!mounted) return;
    final type = data['type'];
    if (type == 'socket_connected') {
      _load(silent: true);
      return;
    }
    if (type == 'listener_online' || type == 'listener_offline') {
      final listenerId = data['listener_id'];
      if (listenerId == null) return;
      final online = type == 'listener_online';
      if (listenerId is int) {
        PresenceCache().setListenerOnline(listenerId, online);
      }
      final idx = _listeners.indexWhere((l) => l['id'] == listenerId);
      if (idx == -1) return;
      if (_listeners[idx]['is_online'] == online &&
          _listeners[idx]['presence_online'] == online) {
        return;
      }
      setState(() {
        _listeners[idx]['is_online'] = online;
        _listeners[idx]['presence_online'] = online;
        _reorder();
      });
    } else if (type == 'listener_presence') {
      final listenerId = data['listener_id'];
      if (listenerId == null) return;
      final presenceOnline = data['presence_online'] == true;
      if (listenerId is int) {
        PresenceCache().setListenerOnline(listenerId, presenceOnline);
      }
      final idx = _listeners.indexWhere((l) => l['id'] == listenerId);
      if (idx == -1) return;
      if (_listeners[idx]['presence_online'] == presenceOnline) return;
      setState(() {
        _listeners[idx]['presence_online'] = presenceOnline;
        _reorder();
      });
    } else if (type == 'listener_call_status') {
      // A listener just accepted or ended a call — flip their card between
      // "In call" and their normal online/offline status.
      final listenerId = data['listener_id'];
      if (listenerId == null) return;
      final inCall = data['is_in_call'] == true;
      final idx = _listeners.indexWhere((l) => l['id'] == listenerId);
      if (idx == -1) return;
      if (_listeners[idx]['is_in_call'] == inCall) return;
      setState(() {
        _listeners[idx]['is_in_call'] = inCall;
      });
    } else if (type == 'listener_rating_updated') {
      final listenerId = data['listener_id'];
      if (listenerId == null) return;
      final idx = _listeners.indexWhere((l) => l['id'] == listenerId);
      if (idx == -1) return;
      setState(() {
        _listeners[idx]['avg_rating'] = data['avg_rating'];
        _listeners[idx]['rating_count'] = data['rating_count'];
      });
    } else if (type == 'coins_updated') {
      final coins = data['coins'];
      if (coins is! int || coins == _profileCoins) return;
      UserDataCache().updateCoins(coins);
      setState(() => _profileCoins = coins);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerMode?.removeListener(_onVisibilityChanged);
    _socketSub?.cancel();
    _pollTimer?.cancel();
    _offersAutoScrollTimer?.cancel();
    _offersController.dispose();
    _offersPage.dispose();
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
      if (token == null) return;
      final listeners = await _repository.getListeners(
        token,
        forceRefresh: forceRefresh,
      );
      final me = await _repository.getMe(token);
      if (requestId != _loadRequestId || !mounted) return;
      final newName = me['name'] ?? '';
      final newPhoto = me['photo_url'];
      final newCoins = me['coins'] ?? 0;
      final newVideoCallEnabled = me['video_call_enabled'] ?? true;
      final newVideoCallDisabledByAdmin =
          me['video_call_disabled_by_admin'] ?? false;
      final changed =
          dataChanged(_listeners, listeners) ||
          _profileName != newName ||
          _profilePhotoUrl != newPhoto ||
          _profileCoins != newCoins ||
          _videoCallEnabled != newVideoCallEnabled ||
          _videoCallDisabledByAdmin != newVideoCallDisabledByAdmin;
      if (changed) {
        setState(() {
          _setListeners(listeners);
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
    } catch (e) {
      if (requestId != _loadRequestId || !mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _callListener(int listenerId, {bool video = false}) async {
    if (_callingListenerId != null) return;
    if (ActiveCallManager.instance.hasActiveCall) {
      PillMessage.show(context, 'You are already on a call', bottomOffset: 78);
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
    } on InsufficientCoinsException {
      if (mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const UpgradeScreen()));
      }
    } catch (e) {
      if (mounted) {
        PillMessage.showError(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          bottomOffset: 78,
        );
      }
    } finally {
      if (mounted) setState(() => _callingListenerId = null);
    }
  }

  void _showVideoDisabledByAdmin() {
    PillMessage.show(
      context,
      'Admin has disabled video calls for your account',
      bottomOffset: 78,
    );
  }

  void _showListenerVideoDisabled() {
    PillMessage.show(
      context,
      'This listener has their video call disabled',
      bottomOffset: 78,
    );
  }

  void _openChat(Map<String, dynamic> listener) {
    Navigator.of(context).push(
      slideRoute(
        ChatHistoryScreen(
          listenerId: listener['id'],
          listenerName: listener['name'],
          listenerPhotoUrl: listener['photo_url'],
          listenerBadgeTag: listener['badge_tag'] as Map<String, dynamic>?,
        ),
      ),
    );
  }

  void _openListenerProfile(Map<String, dynamic> listener) {
    Navigator.of(
      context,
    ).push(slideRoute(ListenerProfileViewScreen(listenerId: listener['id'])));
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = 32 + MediaQuery.paddingOf(context).bottom + 90;
    return Scaffold(
      backgroundColor: _AppColors.bg,
      body: RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(5, 24, 5, 0),
              sliver: SliverToBoxAdapter(child: _buildOffersSection()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(5, 32, 5, 0),
              sliver: SliverToBoxAdapter(child: _buildFeaturedHeader()),
            ),
            ..._buildFeaturedBody(bottomPadding),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFeaturedBody(double bottomPadding) {
    if (_loading ||
        (_error != null && _listeners.isEmpty) ||
        _ordered.isEmpty) {
      final String? message = _loading
          ? null
          : (_error != null && _listeners.isEmpty
                ? _error
                : 'No listeners available');
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: message == null
                  ? const CircularProgressIndicator()
                  : Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _AppColors.textMuted),
                    ),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(5, 8, 5, bottomPadding),
        sliver: SliverList.separated(
          itemCount: _ordered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final listener = _ordered[index];
            return _ListenerCard(
              key: ValueKey<Object?>(listener['id']),
              listener: listener,
              isCalling: _callingListenerId == listener['id'],
                  canAct: _callingListenerId == null &&
                  listener['is_online'] == true,
              videoCallEnabled: _videoCallEnabled,
              videoCallDisabledByAdmin: _videoCallDisabledByAdmin,
              onOpenChat: () => _openChat(listener),
              onOpenProfile: () => _openListenerProfile(listener),
              onAudioCall: () => _callListener(listener['id']),
              onVideoCall: () => _callListener(listener['id'], video: true),
              onVideoBlocked: _showVideoDisabledByAdmin,
              onListenerVideoBlocked: _showListenerVideoDisabled,
            );
          },
        ),
      ),
    ];
  }

  Widget _buildProfileDrawer() {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: DecoratedBox(
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
                      color: _AppColors.brandRed.withValues(alpha: 0.5),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: AvatarImage(
                  photoUrl: _profilePhotoUrl,
                  radius: 44,
                  iconSize: 44,
                ),
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
  static const _dummyOffers = [
    _DummyOfferCard(
      badge: 'WELCOME',
      title: 'Welcome! Let’s Get Started',
      gradient: LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF1A1A1A)]),
    ),
    _DummyOfferCard(
      badge: 'HELLO',
      title: 'Nice to Have You Here',
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_AppColors.brandRed, Color(0xFF681A19)],
      ),
    ),
  ];

  Widget _buildOffersSection() {
    final offers = _specialOffers;
    final hasRealOffers = offers.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: PageView.builder(
            controller: _offersController,
            onPageChanged: (index) => _offersPage.value = index,
            itemCount: hasRealOffers ? offers.length : _dummyOffers.length,
            itemBuilder: (context, index) {
              if (!hasRealOffers) return _dummyOffers[index];
              return _SpecialOfferImageCard(
                imageUrl: ApiConstants.resolveMediaUrl(
                  offers[index]['image_url'] as String?,
                ),
              );
            },
          ),
        ),
        if (hasRealOffers && offers.length > 1) ...[
          const SizedBox(height: 10),
          ValueListenableBuilder<int>(
            valueListenable: _offersPage,
            builder: (context, page, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(offers.length, (index) {
                final isActive = index == page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive
                        ? _AppColors.brandRed
                        : _AppColors.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFeaturedHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [SizedBox(height: 10)],
    );
  }
}

class _ListenerCard extends StatelessWidget {
  final Map<String, dynamic> listener;
  final bool isCalling;
  final bool canAct;
  final bool videoCallEnabled;
  final bool videoCallDisabledByAdmin;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenProfile;
  final VoidCallback onAudioCall;
  final VoidCallback onVideoCall;
  final VoidCallback onVideoBlocked;
  final VoidCallback onListenerVideoBlocked;

  const _ListenerCard({
    super.key,
    required this.listener,
    required this.isCalling,
    required this.canAct,
    required this.videoCallEnabled,
    required this.videoCallDisabledByAdmin,
    required this.onOpenChat,
    required this.onOpenProfile,
    required this.onAudioCall,
    required this.onVideoCall,
    required this.onVideoBlocked,
    required this.onListenerVideoBlocked,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOnline = listener['presence_online'] == true;
    final bool isInCall = isOnline && listener['is_in_call'] == true;
    final tags = (listener['tags'] as List?) ?? const [];

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onOpenChat,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _AppColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _AppColors.cardBorder),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: onOpenProfile,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AvatarImage(
                      photoUrl: listener['photo_url'],
                      radius: 50,
                      iconSize: 40,
                      badgeLabel: AvatarImage.badgeLabelOf(
                        listener['badge_tag'],
                      ),
                      badgeColor: AvatarImage.badgeColorOf(
                        listener['badge_tag'],
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: isInCall
                              ? Colors.orange
                              : (isOnline
                                    ? _AppColors.online
                                    : Colors.grey.shade600),
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
              Expanded(child: _details(isOnline, isInCall, tags)),
              const SizedBox(width: 8),
              if (videoCallEnabled) ...[
                _videoButton(),
                const SizedBox(width: 6),
              ],
              _audioButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _details(bool isOnline, bool isInCall, List<dynamic> tags) {
    final occupation = listener['occupation'] as String?;
    final rating = listener['avg_rating'];
    return Column(
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
          'Age: ${listener['age']?.toString() ?? '...'} · '
          '${occupation != null && occupation.isNotEmpty ? occupation : '...'}',
          style: const TextStyle(fontSize: 12, color: _AppColors.textMuted),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              isInCall ? 'In call' : (isOnline ? 'Online now' : 'Offline'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: isInCall
                    ? Colors.orange
                    : (isOnline ? _AppColors.online : _AppColors.textMuted),
              ),
            ),
            if (rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 14),
                  const SizedBox(width: 2),
                  Text(
                    '$rating',
                    style: const TextStyle(fontSize: 13, color: Colors.amber),
                  ),
                ],
              ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          _CyclingTagsRow(tags: tags),
        ],
      ],
    );
  }

  Widget _videoButton() {
    if (isCalling) return const SizedBox(width: 40, height: 40);
    final bool listenerVideoEnabled = listener['video_call_enabled'] != false;
    final bool blocked = videoCallDisabledByAdmin || !listenerVideoEnabled;
    return InkWell(
      onTap: !canAct
          ? null
          : (videoCallDisabledByAdmin
                ? onVideoBlocked
                : (!listenerVideoEnabled
                      ? onListenerVideoBlocked
                      : onVideoCall)),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: blocked
              ? _AppColors.brandRed.withValues(alpha: 0.2)
              : _AppColors.brandRed.withValues(alpha: canAct ? 0.85 : 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.videocam,
          color: blocked ? Colors.white38 : Colors.white,
          size: 18,
        ),
      ),
    );
  }

  Widget _audioButton() {
    if (isCalling) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _AppColors.brandRed,
          ),
        ),
      );
    }
    return InkWell(
      onTap: canAct ? onAudioCall : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: canAct
              ? _AppColors.brandRed
              : _AppColors.brandRed.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.call, color: Colors.white, size: 18),
      ),
    );
  }
}

class _CyclingTagsRow extends StatefulWidget {
  final List<dynamic> tags;

  const _CyclingTagsRow({required this.tags});

  @override
  State<_CyclingTagsRow> createState() => _CyclingTagsRowState();
}

class _CyclingTagsRowState extends State<_CyclingTagsRow> {
  static const _pageSize = 2;
  Timer? _timer;
  int _page = 0;

  int get _pageCount => (widget.tags.length / _pageSize).ceil();

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
  }

  @override
  void didUpdateWidget(covariant _CyclingTagsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tags != widget.tags) {
      _page = 0;
      _timer?.cancel();
      _maybeStartTimer();
    }
  }

  void _maybeStartTimer() {
    if (_pageCount <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _page = (_page + 1) % _pageCount);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = _page * _pageSize;
    final visible = widget.tags.skip(start).take(_pageSize);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final tag in visible)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _AppColors.brandRed.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$tag',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
      ],
    );
  }
}
