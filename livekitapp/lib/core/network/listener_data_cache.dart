import 'package:livekitapp/core/network/chat_draft_cache.dart';
import 'package:livekitapp/core/network/chat_message_cache.dart';
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/core/network/presence_cache.dart';
import 'package:livekitapp/core/network/typing_cache.dart';

/// Process-wide cache for the listener-side data that almost every screen
/// needs: the profile (`me`), the wallet, the user catalogue and the chat
/// threads.
///
/// Mirrors [UserDataCache]: `cachedX` is the *fresh* value used to decide
/// whether a network call is needed, `lastX` is the last known value (restored
/// from disk on app start) used to paint the first frame. Invalidation only
/// clears the freshness timestamp, never the data.
class ListenerDataCache {
  static final ListenerDataCache _instance = ListenerDataCache._internal();
  factory ListenerDataCache() => _instance;
  ListenerDataCache._internal();

  static const _ttl = Duration(seconds: 20);

  static const _meSnapshotKey = 'listener_me_snapshot';
  static const _threadsSnapshotKey = 'listener_threads_snapshot';
  static const _usersSnapshotKey = 'listener_users_snapshot';
  static const _walletSnapshotKey = 'listener_wallet_snapshot';
  static const _reviewsSnapshotKey = 'listener_reviews_snapshot';

  Map<String, dynamic>? _me;
  DateTime? _meFetchedAt;

  List<Map<String, dynamic>>? _users;
  DateTime? _usersFetchedAt;

  List<Map<String, dynamic>>? _threads;
  DateTime? _threadsFetchedAt;

  Map<String, dynamic>? _wallet;
  DateTime? _walletFetchedAt;

  List<Map<String, dynamic>>? _reviews;
  DateTime? _reviewsFetchedAt;

  bool get _meFresh =>
      _me != null &&
      _meFetchedAt != null &&
      DateTime.now().difference(_meFetchedAt!) < _ttl;

  bool get _usersFresh =>
      _users != null &&
      _usersFetchedAt != null &&
      DateTime.now().difference(_usersFetchedAt!) < _ttl;

  bool get _threadsFresh =>
      _threads != null &&
      _threadsFetchedAt != null &&
      DateTime.now().difference(_threadsFetchedAt!) < _ttl;

  bool get _walletFresh =>
      _wallet != null &&
      _walletFetchedAt != null &&
      DateTime.now().difference(_walletFetchedAt!) < _ttl;

  bool get _reviewsFresh =>
      _reviews != null &&
      _reviewsFetchedAt != null &&
      DateTime.now().difference(_reviewsFetchedAt!) < _ttl;

  Map<String, dynamic>? get cachedMe => _meFresh ? _me : null;
  List<Map<String, dynamic>>? get cachedUsers => _usersFresh ? _users : null;
  List<Map<String, dynamic>>? get cachedThreads =>
      _threadsFresh ? _threads : null;
  Map<String, dynamic>? get cachedWallet => _walletFresh ? _wallet : null;
  List<Map<String, dynamic>>? get cachedReviews =>
      _reviewsFresh ? _reviews : null;

  /// Last known values, ignoring freshness. Meant for painting the first frame.
  Map<String, dynamic>? get lastMe => _me;
  List<Map<String, dynamic>>? get lastUsers => _users;
  List<Map<String, dynamic>>? get lastThreads => _threads;
  Map<String, dynamic>? get lastWallet => _wallet;
  List<Map<String, dynamic>>? get lastReviews => _reviews;

  /// The cached thread for [userId], or an empty map when unknown.
  Map<String, dynamic> thread(int userId) {
    final threads = _threads;
    if (threads == null) return const {};
    for (final thread in threads) {
      if (thread['user_id'] == userId) return thread;
    }
    return const {};
  }

  /// Rehydrates the cache from disk. Call once during app start-up, before the
  /// first frame, so screens open with real data instead of placeholders.
  Future<void> restore() async {
    try {
      if (_me == null) {
        final me = await HomeCache().getJson(_meSnapshotKey);
        if (me is Map) _me = Map<String, dynamic>.from(me);
      }
      if (_threads == null) {
        final threads = await HomeCache().getJson(_threadsSnapshotKey);
        if (threads is List) {
          _threads = threads
              .whereType<Map>()
              .map((t) => Map<String, dynamic>.from(t))
              .toList();
          PresenceCache().seedFromListenerThreads(_threads!);
        }
      }
      if (_users == null) {
        final users = await HomeCache().getJson(_usersSnapshotKey);
        if (users is List) {
          _users = users
              .whereType<Map>()
              .map((u) => Map<String, dynamic>.from(u))
              .toList();
          PresenceCache().seedFromUserCatalogue(_users!);
        }
      }
      if (_wallet == null) {
        final wallet = await HomeCache().getJson(_walletSnapshotKey);
        if (wallet is Map) _wallet = Map<String, dynamic>.from(wallet);
      }
      if (_reviews == null) {
        final reviews = await HomeCache().getJson(_reviewsSnapshotKey);
        if (reviews is List) {
          _reviews = reviews
              .whereType<Map>()
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
        }
      }
    } catch (_) {
      // A corrupt snapshot must never block start-up.
    }
  }

  void setMe(Map<String, dynamic> data) {
    _me = data;
    _meFetchedAt = DateTime.now();
    HomeCache().setJson(_meSnapshotKey, data);
  }

  void setUsers(List<Map<String, dynamic>> data) {
    _users = data;
    _usersFetchedAt = DateTime.now();
    PresenceCache().seedFromUserCatalogue(data);
    HomeCache().setJson(_usersSnapshotKey, data);
  }

  void setThreads(List<Map<String, dynamic>> data) {
    _threads = data;
    _threadsFetchedAt = DateTime.now();
    PresenceCache().seedFromListenerThreads(data);
    HomeCache().setJson(_threadsSnapshotKey, data);
  }

  void setWallet(Map<String, dynamic> data) {
    _wallet = data;
    _walletFetchedAt = DateTime.now();
    HomeCache().setJson(_walletSnapshotKey, data);
  }

  void setReviews(List<Map<String, dynamic>> data) {
    _reviews = data;
    _reviewsFetchedAt = DateTime.now();
    HomeCache().setJson(_reviewsSnapshotKey, data);
  }

  /// Marks the entry stale without dropping it, so it can still paint while a
  /// background refresh is in flight.
  void invalidateMe() => _meFetchedAt = null;

  void invalidateUsers() => _usersFetchedAt = null;

  void invalidateThreads() => _threadsFetchedAt = null;

  void invalidateWallet() => _walletFetchedAt = null;

  void invalidateReviews() => _reviewsFetchedAt = null;

  void clear() {
    _me = null;
    _meFetchedAt = null;
    _users = null;
    _usersFetchedAt = null;
    _threads = null;
    _threadsFetchedAt = null;
    _wallet = null;
    _walletFetchedAt = null;
    _reviews = null;
    _reviewsFetchedAt = null;
    ChatMessageCache().clear();
    ChatDraftCache().clearAll();
    PresenceCache().clear();
    TypingCache().clear();
    HomeCache().clear(_meSnapshotKey);
    HomeCache().clear(_threadsSnapshotKey);
    HomeCache().clear(_usersSnapshotKey);
    HomeCache().clear(_walletSnapshotKey);
    HomeCache().clear(_reviewsSnapshotKey);
  }
}
