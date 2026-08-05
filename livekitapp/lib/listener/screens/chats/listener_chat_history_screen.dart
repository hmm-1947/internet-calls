import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/chat_notification_service.dart';
import 'package:livekitapp/common/utils/chat_message_merge.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/chat_composer.dart';
import 'package:livekitapp/common/widgets/chat_message_list.dart';
import 'package:livekitapp/core/network/chat_message_cache.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/chat_storage.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/presence_cache.dart';
import 'package:livekitapp/common/services/voice_message_player.dart';
import 'package:livekitapp/core/network/voice_note_cache.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/calls/listener_call_notes_screen.dart';
import 'package:livekitapp/listener/screens/user_profile_view_screen.dart';
import 'package:uuid/uuid.dart';

class ListenerChatHistoryScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final String? userPhotoUrl;

  const ListenerChatHistoryScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
  });

  @override
  State<ListenerChatHistoryScreen> createState() =>
      _ListenerChatHistoryScreenState();
}

class _ListenerChatHistoryScreenState extends State<ListenerChatHistoryScreen>
    with WidgetsBindingObserver, RouteAware {
  static const _bg = Color(0xFF0B0F1A);
  static const _pink = Color(0xFFE53950);
  static const _green = Color(0xFF74D8BD);

  static const _statusRank = <String, int>{
    'failed': 0,
    'sending': 0,
    'queued': 0,
    'sent': 1,
    'delivered': 2,
    'read': 3,
  };

  final _pendingReadIds = <int>{};
  final _pendingReadClientIds = <String>{};

  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  final _chatStorage = ChatStorage();
  final _scrollController = ScrollController();

  late final ValueNotifier<List<Map<String, dynamic>>> _messages;
  late final ValueNotifier<bool> _favorite;
  final _typing = ValueNotifier<bool>(false);
  final _atBottom = ValueNotifier<bool>(true);

  String? _token;
  StreamSubscription? _socketSub;
  Timer? _typingSendTimer;
  DateTime? _lastTypingSentAt;
  bool _hasMoreOlder = true;
  bool _loadingOlder = false;

  /// Identifies this conversation for the shared voice-note player.
  String get _chatKey => 'listener:${widget.userId}';

  // Route callbacks decide whether the minimized voice-note bar is needed: it
  // is redundant while this chat is the visible route, and wanted as soon as
  // the user navigates away (back button included).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) voiceChatRouteObserver.subscribe(this, route);
  }

  @override
  void didPush() => VoiceMessagePlayer.instance.setVisibleChat(_chatKey);

  @override
  void didPopNext() => VoiceMessagePlayer.instance.setVisibleChat(_chatKey);

  @override
  void didPushNext() => VoiceMessagePlayer.instance.clearVisibleChat(_chatKey);

  @override
  void didPop() => VoiceMessagePlayer.instance.clearVisibleChat(_chatKey);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages = ValueNotifier<List<Map<String, dynamic>>>(
      ChatMessageCache().messages(widget.userId),
    );
    final thread = ListenerDataCache().thread(widget.userId);
    _favorite = ValueNotifier<bool>(thread['is_pinned'] == true);
    _scrollController.addListener(_onScroll);
    // Drops any stacked notification for this chat and keeps new messages from
    // notifying while the conversation is on screen.
    ChatNotificationService.instance.setVisibleConversation(widget.userId);
    _init();
  }

  @override
  void dispose() {
    ChatNotificationService.instance.clearVisibleConversation(widget.userId);
    voiceChatRouteObserver.unsubscribe(this);
    VoiceMessagePlayer.instance.clearVisibleChat(_chatKey);
    WidgetsBinding.instance.removeObserver(this);
    _socketSub?.cancel();
    _typingSendTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messages.dispose();
    _favorite.dispose();
    _typing.dispose();
    _atBottom.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshMessages();
    _refreshThread();
  }

  Future<void> _init() async {
    _token = await _localStorage.getToken();
    final token = _token;
    if (token == null) return;
    if (_messages.value.isEmpty) {
      final cached = await _chatStorage.getMessages(widget.userId);
      if (!mounted) return;
      if (cached.isNotEmpty) _merge(cached.map((m) => m.toJson()).toList());
    }
    ChatSocketService().connect(token, 'listener');
    _socketSub = ChatSocketService().stream.listen(_onSocketMessage);
    _markRead();
    await _refreshMessages();
    _refreshThread();
    _flushPending();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom = position.pixels <= 80;
    if (_atBottom.value != atBottom) _atBottom.value = atBottom;
    if (position.pixels >= position.maxScrollExtent - 200) _loadOlder();
  }

  void _setMessages(List<Map<String, dynamic>> next) {
    ChatMessageCache().save(widget.userId, next);
    _messages.value = next;
  }

  void _merge(List<Map<String, dynamic>> incoming) {
    if (incoming.isEmpty) return;
    _setMessages(mergeChatMessages(_messages.value, incoming));
    _applyReadMarkers();
  }

  void _patch(
    bool Function(Map<String, dynamic> message) test,
    void Function(Map<String, dynamic> message) apply,
  ) {
    final list = _messages.value;
    var changed = false;
    for (final message in list) {
      if (!test(message)) continue;
      apply(message);
      changed = true;
    }
    if (!changed) return;
    _setMessages(List<Map<String, dynamic>>.from(list));
  }

  void _patchStatus(
    bool Function(Map<String, dynamic> message) test,
    Object? status,
  ) {
    if (status is! String) return;
    final rank = _statusRank[status] ?? 0;
    _patch((m) => test(m) && rank > (_statusRank['${m['status']}'] ?? 0), (m) {
      m['status'] = status;
      if (status == 'read') m['is_read'] = true;
    });
  }

  void _rememberRead(List<int> ids, List<String> clientIds) {
    _pendingReadIds.addAll(ids);
    _pendingReadClientIds.addAll(clientIds.where((id) => id.isNotEmpty));
    while (_pendingReadIds.length > 300) {
      _pendingReadIds.remove(_pendingReadIds.first);
    }
    while (_pendingReadClientIds.length > 300) {
      _pendingReadClientIds.remove(_pendingReadClientIds.first);
    }
  }

  void _applyReadMarkers() {
    if (_pendingReadIds.isEmpty && _pendingReadClientIds.isEmpty) return;
    _patchStatus(
      (m) =>
          _pendingReadIds.contains(m['id']) ||
          _pendingReadClientIds.contains(m['client_id']),
      'read',
    );
  }

  void _jumpToLatest() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels == 0) return;
    _scrollController.jumpTo(0);
  }

  Future<void> _refreshMessages() async {
    final token = _token;
    if (token == null) return;
    try {
      final fetched = await _repository.getChatMessages(token, widget.userId);
      if (!mounted) return;
      _merge(fetched);
      await _chatStorage.saveMessages(
        widget.userId,
        fetched
            .map((m) => LocalChatMessage.fromJson(m, widget.userId))
            .toList(),
      );
      await _ackDelivered(fetched);
    } catch (_) {}
  }

  Future<void> _refreshThread() async {
    final token = _token;
    if (token == null) return;
    try {
      final threads = await _repository.getChatThreads(
        token,
        forceRefresh: true,
      );
      if (!mounted) return;
      final thread = threads.firstWhere(
        (t) => t['user_id'] == widget.userId,
        orElse: () => const {},
      );
      if (thread.isEmpty) return;
      _favorite.value = thread['is_pinned'] == true;
    } catch (_) {}
  }

  Future<void> _markRead({int attempt = 0}) async {
    final token = _token;
    if (token == null) return;
    try {
      await _repository.markMessagesRead(token, widget.userId);
    } catch (_) {
      if (!mounted || attempt >= 3) return;
      Future.delayed(Duration(seconds: 2 * (attempt + 1)), () {
        if (mounted) _markRead(attempt: attempt + 1);
      });
    }
  }

  Future<void> _ackDelivered(List<Map<String, dynamic>> messages) async {
    final token = _token;
    if (token == null) return;
    final ids = messages
        .where(
          (m) =>
              m['sender_type'] == 'user' &&
              m['status'] == 'sent' &&
              m['id'] != null,
        )
        .map<int>((m) => m['id'] as int)
        .toList();
    if (ids.isEmpty) return;
    try {
      await _repository.markMessagesDelivered(token, ids);
      await _chatStorage.updateStatusByServerIds(ids, 'delivered');
    } catch (_) {}
  }

  Future<void> _loadOlder() async {
    final token = _token;
    if (_loadingOlder || !_hasMoreOlder || token == null) return;
    final oldestId = _messages.value
        .map((m) => m['id'])
        .whereType<int>()
        .fold<int?>(null, (min, id) => min == null || id < min ? id : min);
    if (oldestId == null) return;
    _loadingOlder = true;
    try {
      final cached = await _chatStorage.getBeforePage(widget.userId, oldestId);
      if (cached.isNotEmpty) {
        if (!mounted) return;
        _merge(cached.map((m) => m.toJson()).toList());
        return;
      }
      final older = await _repository.getChatMessages(
        token,
        widget.userId,
        beforeId: oldestId,
      );
      if (older.isEmpty) {
        _hasMoreOlder = false;
        return;
      }
      await _chatStorage.saveMessages(
        widget.userId,
        older.map((m) => LocalChatMessage.fromJson(m, widget.userId)).toList(),
      );
      if (!mounted) return;
      _merge(older);
    } catch (_) {
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> _flushPending() async {
    final pending = await _chatStorage.getPending();
    for (final message in pending.where((p) => p.otherId == widget.userId)) {
      await _retrySend(message.clientId, message.message);
    }
  }

  void _onSocketMessage(Map<String, dynamic> data) {
    final type = data['type'];
    switch (type) {
      case 'chat_message':
        if (data['user_id'] != widget.userId) return;
        _merge([data]);
        _chatStorage.upsertMessage(
          widget.userId,
          LocalChatMessage.fromJson(data, widget.userId),
        );
        final token = _token;
        if (data['sender_type'] == 'user' && token != null) {
          _markRead();
          final id = data['id'];
          if (id is int) {
            _repository.markMessagesDelivered(token, [id]).catchError((_) {});
          }
        }
        return;
      case 'typing':
        if (data['user_id'] != widget.userId) return;
        _typing.value = data['is_typing'] == true;
        return;
      case 'user_online':
      case 'user_offline':
        if (data['user_id'] != widget.userId) return;
        PresenceCache().setUserOnline(widget.userId, type == 'user_online');
        return;
      case 'message_status':
        final clientId = data['client_id'];
        if (clientId == null) return;
        _patchStatus((m) => m['client_id'] == clientId, data['status']);
        _chatStorage.updateStatus(clientId, data['status']);
        return;
      case 'message_status_bulk':
        final ids = List<int>.from(data['ids'] ?? const []);
        final clientIds = List<String>.from(
          (data['client_ids'] as List? ?? const []).whereType<String>(),
        );
        if (ids.isEmpty && clientIds.isEmpty) return;
        _patchStatus(
          (m) => ids.contains(m['id']) || clientIds.contains(m['client_id']),
          data['status'],
        );
        _chatStorage.updateStatusByServerIds(ids, data['status']);
        return;
      case 'read_receipt':
        if (data['user_id'] != widget.userId) return;
        final ids = List<int>.from(data['message_ids'] ?? const []);
        final clientIds = List<String>.from(
          (data['client_ids'] as List? ?? const []).whereType<String>(),
        );
        if (ids.isEmpty && clientIds.isEmpty) return;
        _rememberRead(ids, clientIds);
        _applyReadMarkers();
        _chatStorage.markReadUpTo(widget.userId, ids);
        _chatStorage.markReadByClientIds(widget.userId, clientIds);
        return;
      case 'socket_connected':
        _refreshMessages();
        return;
      case 'message_edited':
        _merge([data]);
        return;
      case 'message_deleted':
        _patch((m) => m['id'] == data['id'], (m) {
          m['is_deleted'] = true;
          m['message'] = '';
        });
        return;
    }
  }

  void _emitTyping() {
    final now = DateTime.now();
    final last = _lastTypingSentAt;
    if (last == null || now.difference(last) >= const Duration(seconds: 1)) {
      _lastTypingSentAt = now;
      ChatSocketService().sendTyping(userId: widget.userId, isTyping: true);
    }
    _typingSendTimer?.cancel();
    _typingSendTimer = Timer(const Duration(seconds: 2), () {
      _lastTypingSentAt = null;
      ChatSocketService().sendTyping(userId: widget.userId, isTyping: false);
    });
  }

  Future<void> _sendText(String text) async {
    final token = _token;
    if (token == null) return;
    final clientId = const Uuid().v4();
    _merge([
      {
        'client_id': clientId,
        'user_id': widget.userId,
        'sender_type': 'listener',
        'message': text,
        'message_type': 'text',
        'status': 'sending',
        'is_deleted': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    ]);
    _jumpToLatest();
    await _retrySend(clientId, text);
  }

  Future<void> _sendVoice(String filePath, int duration) async {
    final token = _token;
    if (token == null) return;
    final clientId = const Uuid().v4();
    _merge([
      {
        'client_id': clientId,
        'user_id': widget.userId,
        'sender_type': 'listener',
        'message': '',
        'message_type': 'audio',
        'audio_url': filePath,
        'audio_duration': duration,
        'status': 'sending',
        'is_deleted': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    ]);
    _jumpToLatest();
    try {
      final sent = await _repository.sendVoiceMessage(
        token,
        widget.userId,
        filePath,
        duration,
        clientId: clientId,
      );
      // Keep the recording we just uploaded as this device's cached copy so
      // playing back our own note never hits the network.
      await VoiceNoteCache.instance.store(
        '${sent['audio_url'] ?? ''}',
        filePath,
      );
      if (!mounted) return;
      _merge([sent]);
      await _chatStorage.upsertMessage(
        widget.userId,
        LocalChatMessage.fromJson(sent, widget.userId),
      );
    } catch (_) {
      if (!mounted) return;
      _patch((m) => m['client_id'] == clientId, (m) => m['status'] = 'failed');
    }
  }

  Future<void> _retrySend(String clientId, String text) async {
    final token = _token;
    if (token == null) return;
    try {
      final sent = await _repository.sendChatMessage(
        token,
        widget.userId,
        text,
        clientId: clientId,
      );
      await _chatStorage.removePending(clientId);
      await _chatStorage.upsertMessage(
        widget.userId,
        LocalChatMessage.fromJson(sent, widget.userId),
      );
      if (!mounted) return;
      _merge([sent]);
    } catch (_) {
      await _chatStorage.addPending(
        PendingMessage(
          clientId: clientId,
          otherId: widget.userId,
          message: text,
        ),
      );
      if (!mounted) return;
      _patch((m) => m['client_id'] == clientId, (m) => m['status'] = 'failed');
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _retrySend(clientId, text);
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final token = _token;
    if (token == null) return;
    final next = !_favorite.value;
    _favorite.value = next;
    try {
      await _repository.updateChatSettings(
        token,
        widget.userId,
        isPinned: next,
      );
    } catch (_) {
      if (mounted) _favorite.value = !next;
    }
  }

  /// Opens the profile of the user this chat is with. What the app bar is
  /// already showing is passed along so the profile paints without a flash.
  void _openUserProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileViewScreen(
          userId: widget.userId,
          initialName: widget.userName,
          initialPhotoUrl: widget.userPhotoUrl,
          initialIsOnline: PresenceCache().user(widget.userId).value == true,
        ),
      ),
    );
  }

  Widget _subtitle() {
    return SizedBox(
      height: 16,
      child: ValueListenableBuilder<bool>(
        valueListenable: _typing,
        builder: (context, typing, _) {
          return ValueListenableBuilder<bool?>(
            valueListenable: PresenceCache().user(widget.userId),
            builder: (context, online, _) {
              if (!typing && online == null) return const SizedBox.shrink();
              final label = typing
                  ? 'typing...'
                  : (online == true ? 'Online' : 'Offline');
              return Text(
                label,
                style: TextStyle(
                  color: typing
                      ? _pink
                      : (online == true ? _green : Colors.white54),
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 380;
    final iconButtonStyle = IconButton.styleFrom(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 4 : 8),
      minimumSize: const Size(36, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          style: iconButtonStyle,
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // Tapping the avatar/name opens the user's profile, the same gesture
        // every other chat app uses for "who am I talking to?".
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openUserProfile,
          child: Row(
            children: [
              AvatarImage(
                photoUrl: widget.userPhotoUrl,
                radius: isNarrow ? 15 : 18,
                iconSize: isNarrow ? 15 : 18,
                backgroundColor: const Color(0xFF2A3145),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.userName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isNarrow ? 14 : 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    _subtitle(),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            style: iconButtonStyle,
            icon: Icon(
              Icons.note_alt_outlined,
              color: Colors.white,
              size: isNarrow ? 20 : 24,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ListenerCallNotesScreen(
                    userId: widget.userId,
                    otherPartyName: widget.userName,
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _favorite,
            builder: (context, favorite, _) => IconButton(
              style: iconButtonStyle,
              icon: Icon(
                favorite ? Icons.favorite : Icons.favorite_border,
                color: favorite ? _pink : Colors.white,
                size: isNarrow ? 20 : 24,
              ),
              onPressed: _toggleFavorite,
            ),
          ),
          IconButton(
            style: iconButtonStyle,
            icon: Icon(
              Icons.more_vert,
              color: Colors.white,
              size: isNarrow ? 20 : 24,
            ),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                ChatMessageList(
                  messages: _messages,
                  controller: _scrollController,
                  isMine: (message) => message['sender_type'] == 'listener',
                  giftCoins: (message) =>
                      ((message['gift_coins'] ?? 0) as int) ~/ 2,
                  bubbleMinWidth: 56,
                  otherPartyName: widget.userName,
                  chatKey: _chatKey,
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _atBottom,
                    builder: (context, atBottom, _) => atBottom
                        ? const SizedBox.shrink()
                        : FloatingActionButton(
                            mini: true,
                            backgroundColor: const Color(0xFF1F2430),
                            onPressed: () => _scrollController.jumpTo(0),
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          ChatComposer(
            onSendText: _sendText,
            onSendVoice: _sendVoice,
            onTextChanged: _emitTyping,
            accentColor: _pink,
            backgroundColor: _bg,
          ),
        ],
      ),
    );
  }
}
