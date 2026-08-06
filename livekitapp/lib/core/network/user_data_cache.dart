import 'package:flutter/foundation.dart';
import 'package:livekitapp/core/network/chat_draft_cache.dart';
import 'package:livekitapp/core/network/chat_message_cache.dart';
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/core/network/presence_cache.dart';
import 'package:livekitapp/core/network/typing_cache.dart';

/// Last known coin balance, or `null` while it has never been loaded.
///
/// The tri-state is deliberate. A widget that renders `0` for "not loaded yet"
/// is exactly what makes an app bar show `0` for one frame and then flick to the
/// real balance. Listeners must render nothing (ideally inside a fixed-width
/// box, so the surrounding layout does not resize) while the value is `null`.
final ValueNotifier<int?> userCoinsNotifier = ValueNotifier<int?>(null);

/// Process-wide cache for the user-side data that almost every screen needs:
/// the profile (`me`), the listener catalogue and the chat threads.
///
/// Two levels are exposed on purpose:
///
///  * `cachedX`  - value only if it is still *fresh* (within [_ttl]). Callers
///    use this to decide whether a network round-trip is needed.
///  * `lastX`    - last known value regardless of age, restored from disk on
///    app start. Callers use this to paint the very first frame.
///
/// Invalidation only clears the freshness timestamp, never the data, so a stale
/// entry can still be painted immediately while it is refreshed in background.
class UserDataCache {
  static final UserDataCache _instance = UserDataCache._internal();
  factory UserDataCache() => _instance;
  UserDataCache._internal();

  static const _ttl = Duration(seconds: 20);

  static const _meSnapshotKey = 'user_me_snapshot';
  static const _threadsSnapshotKey = 'user_threads_snapshot';

  Map<String, dynamic>? _me;
  DateTime? _meFetchedAt;

  List<Map<String, dynamic>>? _listeners;
  DateTime? _listenersFetchedAt;

  List<Map<String, dynamic>>? _threads;
  DateTime? _threadsFetchedAt;

  bool get _meFresh =>
      _me != null &&
      _meFetchedAt != null &&
      DateTime.now().difference(_meFetchedAt!) < _ttl;

  bool get _listenersFresh =>
      _listeners != null &&
      _listenersFetchedAt != null &&
      DateTime.now().difference(_listenersFetchedAt!) < _ttl;

  bool get _threadsFresh =>
      _threads != null &&
      _threadsFetchedAt != null &&
      DateTime.now().difference(_threadsFetchedAt!) < _ttl;

  Map<String, dynamic>? get cachedMe => _meFresh ? _me : null;
  List<Map<String, dynamic>>? get cachedListeners =>
      _listenersFresh ? _listeners : null;
  List<Map<String, dynamic>>? get cachedThreads =>
      _threadsFresh ? _threads : null;

  /// Last known values, ignoring freshness. Meant for painting the first frame.
  Map<String, dynamic>? get lastMe => _me;
  List<Map<String, dynamic>>? get lastListeners => _listeners;
  List<Map<String, dynamic>>? get lastThreads => _threads;

  /// The cached thread for [listenerId], or an empty map when unknown.
  Map<String, dynamic> thread(int listenerId) {
    final threads = _threads;
    if (threads == null) return const {};
    for (final thread in threads) {
      if (thread['listener_id'] == listenerId) return thread;
    }
    return const {};
  }

  /// Rehydrates the cache from disk. Call once during app start-up, before the
  /// first frame, so screens open with real data instead of placeholders.
  ///
  /// Restored entries carry no freshness timestamp, so the normal background
  /// refresh still runs; they only exist to avoid an empty first paint.
  Future<void> restore() async {
    try {
      if (_me == null) {
        final me = await HomeCache().getJson(_meSnapshotKey);
        if (me is Map) {
          _me = Map<String, dynamic>.from(me);
          final coins = _me!['coins'];
          if (coins is int) userCoinsNotifier.value = coins;
        }
      }
      if (_threads == null) {
        final threads = await HomeCache().getJson(_threadsSnapshotKey);
        if (threads is List) {
          _threads = threads
              .whereType<Map>()
              .map((t) => Map<String, dynamic>.from(t))
              .toList();
          PresenceCache().seedFromUserThreads(_threads!);
        }
      }
    } catch (_) {
      // A corrupt snapshot must never block start-up.
    }
  }

  void setMe(Map<String, dynamic> data) {
    _me = data;
    _meFetchedAt = DateTime.now();
    final coins = data['coins'];
    if (coins is int) userCoinsNotifier.value = coins;
    HomeCache().setJson(_meSnapshotKey, data);
  }

  /// Applies a coin balance pushed over the socket without invalidating the
  /// rest of the profile, so only the coin widgets repaint.
  void updateCoins(int coins) {
    _me?['coins'] = coins;
    userCoinsNotifier.value = coins;
    final me = _me;
    if (me != null) HomeCache().setJson(_meSnapshotKey, me);
  }

  void setListeners(List<Map<String, dynamic>> data) {
    _listeners = data;
    _listenersFetchedAt = DateTime.now();
    PresenceCache().seedFromListenerCatalogue(data);
  }

  void setThreads(List<Map<String, dynamic>> data) {
    _threads = data;
    _threadsFetchedAt = DateTime.now();
    PresenceCache().seedFromUserThreads(data);
    HomeCache().setJson(_threadsSnapshotKey, data);
  }

  /// Marks the entry stale without dropping it: the next read of `cachedMe`
  /// triggers a refetch while `lastMe` can still paint the current frame.
  void invalidateMe() => _meFetchedAt = null;

  void invalidateThreads() => _threadsFetchedAt = null;

  void invalidateListeners() => _listenersFetchedAt = null;

  void clear() {
    _me = null;
    _meFetchedAt = null;
    _listeners = null;
    _listenersFetchedAt = null;
    _threads = null;
    _threadsFetchedAt = null;
    userCoinsNotifier.value = null;
    ChatMessageCache().clear();
    ChatDraftCache().clearAll();
    PresenceCache().clear();
    TypingCache().clear();
    HomeCache().clear(_meSnapshotKey);
    HomeCache().clear(_threadsSnapshotKey);
  }
}
