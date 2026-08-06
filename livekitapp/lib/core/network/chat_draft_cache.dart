import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekitapp/core/network/home_cache.dart';

class ChatDraftCache {
  static final ChatDraftCache _instance = ChatDraftCache._internal();
  factory ChatDraftCache() => _instance;
  ChatDraftCache._internal();

  static const _storageKey = 'chat_drafts';

  /// Bumped whenever any draft changes so the chat list can show or drop the
  /// "Draft" preview without polling.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, String> _drafts = {};
  Timer? _flushTimer;
  Timer? _revisionTimer;
  bool _restored = false;

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final stored = await HomeCache().getJson(_storageKey);
      if (stored is! Map) return;
      stored.forEach((key, value) {
        if (key is String && value is String && value.isNotEmpty) {
          _drafts[key] = value;
        }
      });
      if (_drafts.isNotEmpty) _bumpNow();
    } catch (_) {}
  }

  String? read(String? key) => key == null ? null : _drafts[key];

  void write(String? key, String text) {
    if (key == null) return;
    final had = _drafts.containsKey(key);
    if (text.trim().isEmpty) {
      if (_drafts.remove(key) == null) return;
    } else {
      if (_drafts[key] == text) return;
      _drafts[key] = text;
    }
    // A draft appearing or disappearing changes the chat list layout, so it is
    // published at once; edits inside an existing draft are only a preview and
    // are coalesced to keep a keystroke from repainting the list.
    if (had == _drafts.containsKey(key)) {
      _scheduleBump();
    } else {
      _bumpNow();
    }
    _scheduleFlush();
  }

  void clear(String? key) {
    if (key == null) return;
    if (_drafts.remove(key) == null) return;
    _bumpNow();
    _scheduleFlush();
  }

  void clearAll() {
    if (_drafts.isEmpty) return;
    _drafts.clear();
    _bumpNow();
    _flushTimer?.cancel();
    _flushTimer = null;
    HomeCache().clear(_storageKey);
  }

  void _bumpNow() {
    _revisionTimer?.cancel();
    _revisionTimer = null;
    revision.value++;
  }

  void _scheduleBump() {
    _revisionTimer?.cancel();
    _revisionTimer = Timer(const Duration(milliseconds: 400), _bumpNow);
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 400), _flush);
  }

  Future<void> _flush() async {
    _flushTimer = null;
    try {
      await HomeCache().setJson(_storageKey, _drafts);
    } catch (_) {}
  }

  Future<void> flushNow() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_revisionTimer != null) _bumpNow();
    await _flush();
  }
}
