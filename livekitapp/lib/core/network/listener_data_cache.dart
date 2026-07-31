import 'package:livekitapp/core/network/chat_message_cache.dart';
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/core/network/presence_cache.dart';

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

  Map<String, dynamic>? _me;
  DateTime? _meFetchedAt;

  List<Map<String, dynamic>>? _users;
  DateTime? _usersFetchedAt;

  List<Map<String, dynamic>>? _threads;
  DateTime? _threadsFetchedAt;

  Map<String, dynamic>? _wallet;
  DateTime? _walletFetchedAt;

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

  Map<String, dynamic>? get cachedMe => _meFresh ? _me : null;
  List<Map<String, dynamic>>? get cachedUsers => _usersFresh ? _users : null;
  List<Map<String, dynamic>>? get cachedThreads =>
      _threadsFresh ? _threads : null;
  Map<String, dynamic>? get cachedWallet => _walletFresh ? _wallet : null;

  /// Last known values, ignoring freshness. Meant for painting the first frame.
  Map<String, dynamic>? get lastMe => _me;
  List<Map<String, dynamic>>? get lastUsers => _users;
  List<Map<String, dynamic>>? get lastThreads => _threads;
  Map<String, dynamic>? get lastWallet => _wallet;

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
  }

  /// Marks the entry stale without dropping it, so it can still paint while a
  /// background refresh is in flight.
  void invalidateMe() => _meFetchedAt = null;

  void invalidateUsers() => _usersFetchedAt = null;

  void invalidateThreads() => _threadsFetchedAt = null;

  void invalidateWallet() => _walletFetchedAt = null;

  void clear() {
    _me = null;
    _meFetchedAt = null;
    _users = null;
    _usersFetchedAt = null;
    _threads = null;
    _threadsFetchedAt = null;
    _wallet = null;
    _walletFetchedAt = null;
    ChatMessageCache().clear();
    PresenceCache().clear();
    HomeCache().clear(_meSnapshotKey);
    HomeCache().clear(_threadsSnapshotKey);
  }
}
