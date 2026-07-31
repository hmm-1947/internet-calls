import 'package:flutter/foundation.dart';

/// Process-wide online/offline (presence) cache.
///
/// Presence is exposed as one [ValueNotifier] per peer so the widgets that show
/// it (a chat app-bar subtitle, an avatar dot in the chat list) can repaint on
/// their own. Nothing else on the screen rebuilds when presence changes, which
/// is what keeps the chat layout and the scroll offset perfectly stable while
/// presence updates arrive over the socket.
///
/// The value is deliberately tri-state:
///  * `null`  -> unknown yet, render nothing (never render a wrong "Offline")
///  * `true`  -> online
///  * `false` -> offline
class PresenceCache {
  static final PresenceCache _instance = PresenceCache._internal();
  factory PresenceCache() => _instance;
  PresenceCache._internal();

  final Map<int, ValueNotifier<bool?>> _listeners = {};
  final Map<int, ValueNotifier<bool?>> _users = {};

  /// Presence of a listener, as seen from the user app.
  ValueNotifier<bool?> listener(int listenerId) =>
      _listeners.putIfAbsent(listenerId, () => ValueNotifier<bool?>(null));

  /// Presence of a user, as seen from the listener app.
  ValueNotifier<bool?> user(int userId) =>
      _users.putIfAbsent(userId, () => ValueNotifier<bool?>(null));

  void setListenerOnline(int listenerId, bool? online) =>
      _set(listener(listenerId), online);

  void setUserOnline(int userId, bool? online) => _set(user(userId), online);

  /// Assigning the same value is a no-op: [ValueNotifier] only notifies when
  /// the value actually changes, so repeated background refreshes that return
  /// unchanged presence never trigger a rebuild.
  void _set(ValueNotifier<bool?> notifier, bool? online) {
    if (notifier.value == online) return;
    notifier.value = online;
  }

  /// Seeds presence from the user-side chat threads payload so that opening a
  /// chat already knows the peer state and does not flip from "Offline" to
  /// "Online" a second later.
  void seedFromUserThreads(List<Map<String, dynamic>> threads) {
    for (final thread in threads) {
      final id = thread['listener_id'];
      if (id is int) setListenerOnline(id, thread['is_online'] == true);
    }
  }

  /// Seeds presence from the listener-side chat threads payload.
  void seedFromListenerThreads(List<Map<String, dynamic>> threads) {
    for (final thread in threads) {
      final id = thread['user_id'];
      if (id is int) setUserOnline(id, thread['is_online'] == true);
    }
  }

  void seedFromListenerCatalogue(List<Map<String, dynamic>> listeners) {
    for (final listener in listeners) {
      final id = listener['id'];
      if (id is int) setListenerOnline(id, listener['is_online'] == true);
    }
  }

  void seedFromUserCatalogue(List<Map<String, dynamic>> users) {
    for (final user in users) {
      final id = user['id'];
      if (id is int) setUserOnline(id, user['is_online'] == true);
    }
  }

  /// Drops every known value back to "unknown" (used on logout).
  void clear() {
    for (final notifier in _listeners.values) {
      notifier.value = null;
    }
    for (final notifier in _users.values) {
      notifier.value = null;
    }
  }
}
