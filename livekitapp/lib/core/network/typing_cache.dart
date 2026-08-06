import 'dart:async';

import 'package:flutter/foundation.dart';

/// Process-wide "peer is typing" cache.
///
/// Typing is exposed as one [ValueNotifier] per peer, exactly like
/// [PresenceCache], so the chat app-bar subtitle and the chat list tile can
/// repaint on their own without rebuilding the screen around them.
///
/// Every `true` is stored with an expiry timer. A peer that stops sending
/// typing events (it closed the chat, lost the socket, or the `false` event was
/// dropped) therefore falls back to "not typing" on its own instead of leaving
/// the indicator stuck until the screen is reopened.
class TypingCache {
  static final TypingCache _instance = TypingCache._internal();
  factory TypingCache() => _instance;
  TypingCache._internal();

  static const _expiry = Duration(seconds: 5);

  final Map<int, ValueNotifier<bool>> _listeners = {};
  final Map<int, ValueNotifier<bool>> _users = {};
  final Map<int, Timer> _listenerTimers = {};
  final Map<int, Timer> _userTimers = {};

  /// Whether a listener is typing, as seen from the user app.
  ValueNotifier<bool> listener(int listenerId) =>
      _listeners.putIfAbsent(listenerId, () => ValueNotifier<bool>(false));

  /// Whether a user is typing, as seen from the listener app.
  ValueNotifier<bool> user(int userId) =>
      _users.putIfAbsent(userId, () => ValueNotifier<bool>(false));

  void setListenerTyping(int listenerId, bool typing) =>
      _set(listener(listenerId), _listenerTimers, listenerId, typing);

  void setUserTyping(int userId, bool typing) =>
      _set(user(userId), _userTimers, userId, typing);

  void _set(
    ValueNotifier<bool> notifier,
    Map<int, Timer> timers,
    int id,
    bool typing,
  ) {
    timers.remove(id)?.cancel();
    if (notifier.value != typing) notifier.value = typing;
    if (!typing) return;
    timers[id] = Timer(_expiry, () {
      timers.remove(id);
      notifier.value = false;
    });
  }

  /// Drops every indicator. Used when the socket goes down, when the app leaves
  /// the foreground and on logout: whatever was true is no longer trustworthy.
  void clear() {
    for (final timer in _listenerTimers.values) {
      timer.cancel();
    }
    for (final timer in _userTimers.values) {
      timer.cancel();
    }
    _listenerTimers.clear();
    _userTimers.clear();
    for (final notifier in _listeners.values) {
      notifier.value = false;
    }
    for (final notifier in _users.values) {
      notifier.value = false;
    }
  }
}
