import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/services/chat_notification_service.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/chat_composer.dart';
import 'package:livekitapp/common/widgets/chat_message_list.dart';
import 'package:livekitapp/common/widgets/typing_indicator.dart';
import 'package:livekitapp/common/utils/chat_message_merge.dart';
import 'package:livekitapp/core/network/chat_message_cache.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/chat_storage.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/presence_cache.dart';
import 'package:livekitapp/core/network/typing_cache.dart';
import 'package:livekitapp/core/network/user_data_cache.dart';
import 'package:livekitapp/common/services/voice_message_player.dart';
import 'package:livekitapp/core/network/voice_note_cache.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/listener_profile_view_screen.dart';
import 'package:livekitapp/user/widgets/gift_sheet.dart';
import 'package:uuid/uuid.dart';

class ChatHistoryScreen extends StatefulWidget {
  final int listenerId;
  final String listenerName;
  final String? listenerPhotoUrl;

  const ChatHistoryScreen({
    super.key,
    required this.listenerId,
    required this.listenerName,
    this.listenerPhotoUrl,
  });

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen>
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

  /// Keys of gift messages that arrived via the socket while this screen was
  /// already open. These are shown as separate bubbles instead of being
  /// stacked — only gifts already present when the chat loaded are stacked.
  final _liveMessageKeys = <String>{};

  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  final _chatStorage = ChatStorage();
  final _scrollController = ScrollController();

  late final ValueNotifier<List<Map<String, dynamic>>> _messages;
  late final ValueNotifier<bool> _favorite;
  late final ValueNotifier<bool> _videoCallAvailable;
  final _atBottom = ValueNotifier<bool>(true);

  String? _token;
  StreamSubscription? _socketSub;
  Timer? _typingSendTimer;
  DateTime? _lastTypingSentAt;
  bool _hasMoreOlder = true;
  bool _loadingOlder = false;
  bool _callingListener = false;
  int _chatMessageCoinCost =
      UserDataCache().lastMe?['chat_message_coin_cost'] ?? 0;

  /// Identifies this conversation for the shared voice-note player.
  String get _chatKey => 'user:${widget.listenerId}';

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
  void didPushNext() {
    VoiceMessagePlayer.instance.clearVisibleChat(_chatKey);
    _stopTyping();
  }

  @override
  void didPop() {
    VoiceMessagePlayer.instance.clearVisibleChat(_chatKey);
    _stopTyping();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages = ValueNotifier<List<Map<String, dynamic>>>(
      ChatMessageCache().messages(widget.listenerId),
    );
    final thread = UserDataCache().thread(widget.listenerId);
    _favorite = ValueNotifier<bool>(thread['is_pinned'] == true);
    final me = UserDataCache().lastMe;
    _videoCallAvailable = ValueNotifier<bool>(
      (me?['video_call_enabled'] ?? true) == true &&
          (me?['video_call_disabled_by_admin'] ?? false) != true,
    );
    _scrollController.addListener(_onScroll);
    // Drops any stacked notification for this chat and keeps new messages from
    // notifying while the conversation is on screen.
    ChatNotificationService.instance.setVisibleConversation(widget.listenerId);
    _init();
  }

  @override
  void dispose() {
    _stopTyping();
    ChatNotificationService.instance.clearVisibleConversation(
      widget.listenerId,
    );
    voiceChatRouteObserver.unsubscribe(this);
    VoiceMessagePlayer.instance.clearVisibleChat(_chatKey);
    WidgetsBinding.instance.removeObserver(this);
    _socketSub?.cancel();
    _typingSendTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messages.dispose();
    _favorite.dispose();
    _videoCallAvailable.dispose();
    _atBottom.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopTyping();
      _setPeerTyping(false);
      return;
    }
    _refreshMessages();
    _refreshProfile();
    _refreshThread();
  }

  Future<void> _init() async {
    _token = await _localStorage.getToken();
    final token = _token;
    if (token == null) return;
    if (_messages.value.isEmpty) {
      final cached = await _chatStorage.getMessages(widget.listenerId);
      if (!mounted) return;
      if (cached.isNotEmpty) _merge(cached.map((m) => m.toJson()).toList());
    }
    ChatSocketService().connect(token, 'user');
    _socketSub = ChatSocketService().stream.listen(_onSocketMessage);
    _markRead();
    await _refreshMessages();
    _refreshProfile();
    _refreshThread();
    _refreshPresence();
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
    ChatMessageCache().save(widget.listenerId, next);
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

  void _removeMessage(String clientId) {
    final list = List<Map<String, dynamic>>.from(_messages.value)
      ..removeWhere((m) => m['client_id'] == clientId);
    _setMessages(list);
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
      final fetched = await _repository.getChatMessages(
        token,
        widget.listenerId,
      );
      if (!mounted) return;
      _merge(fetched);
      await _chatStorage.saveMessages(
        widget.listenerId,
        fetched
            .map((m) => LocalChatMessage.fromJson(m, widget.listenerId))
            .toList(),
      );
      await _ackDelivered(fetched);
    } catch (_) {}
  }

  Future<void> _refreshProfile() async {
    final token = _token;
    if (token == null) return;
    try {
      final me = await _repository.getMe(token, forceRefresh: true);
      if (!mounted) return;
      _chatMessageCoinCost = me['chat_message_coin_cost'] ?? 0;
      _videoCallAvailable.value =
          (me['video_call_enabled'] ?? true) == true &&
          (me['video_call_disabled_by_admin'] ?? false) != true;
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
        (t) => t['listener_id'] == widget.listenerId,
        orElse: () => const {},
      );
      if (thread.isEmpty) return;
      _favorite.value = thread['is_pinned'] == true;
    } catch (_) {}
  }

  Future<void> _refreshPresence() async {
    final token = _token;
    if (token == null) return;
    try {
      final profile = await _repository.getListenerProfile(
        token,
        widget.listenerId,
      );
      PresenceCache().setListenerOnline(
        widget.listenerId,
        profile['is_online'] == true,
      );
    } catch (_) {}
  }

  Future<void> _markRead({int attempt = 0}) async {
    final token = _token;
    if (token == null) return;
    try {
      await _repository.markMessagesRead(token, widget.listenerId);
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
              m['sender_type'] == 'listener' &&
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
      final cached = await _chatStorage.getBeforePage(
        widget.listenerId,
        oldestId,
      );
      if (cached.isNotEmpty) {
        if (!mounted) return;
        _merge(cached.map((m) => m.toJson()).toList());
        return;
      }
      final older = await _repository.getChatMessages(
        token,
        widget.listenerId,
        beforeId: oldestId,
      );
      if (older.isEmpty) {
        _hasMoreOlder = false;
        return;
      }
      await _chatStorage.saveMessages(
        widget.listenerId,
        older
            .map((m) => LocalChatMessage.fromJson(m, widget.listenerId))
            .toList(),
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
    for (final message in pending.where(
      (p) => p.otherId == widget.listenerId,
    )) {
      await _retrySend(message.clientId, message.message);
    }
  }

  void _onSocketMessage(Map<String, dynamic> data) {
    final type = data['type'];
    switch (type) {
      case 'chat_message':
        if (data['listener_id'] != widget.listenerId) return;
        _liveMessageKeys.add(chatMessageKey(data));
        if (data['sender_type'] == 'listener') _setPeerTyping(false);
        _merge([data]);
        _chatStorage.upsertMessage(
          widget.listenerId,
          LocalChatMessage.fromJson(data, widget.listenerId),
        );
        final token = _token;
        if (data['sender_type'] == 'listener' && token != null) {
          _markRead();
          final id = data['id'];
          if (id is int) {
            _repository.markMessagesDelivered(token, [id]).catchError((_) {});
          }
        }
        return;
      case 'typing':
        if (data['listener_id'] != widget.listenerId) return;
        _setPeerTyping(data['is_typing'] == true);
        return;
      case 'listener_online':
      case 'listener_offline':
        if (data['listener_id'] != widget.listenerId) return;
        final online = type == 'listener_online';
        if (!online) _setPeerTyping(false);
        PresenceCache().setListenerOnline(widget.listenerId, online);
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
        if (data['listener_id'] != widget.listenerId) return;
        final ids = List<int>.from(data['message_ids'] ?? const []);
        final clientIds = List<String>.from(
          (data['client_ids'] as List? ?? const []).whereType<String>(),
        );
        if (ids.isEmpty && clientIds.isEmpty) return;
        _rememberRead(ids, clientIds);
        _applyReadMarkers();
        _chatStorage.markReadUpTo(widget.listenerId, ids);
        _chatStorage.markReadByClientIds(widget.listenerId, clientIds);
        return;
      case 'socket_connected':
        _setPeerTyping(false);
        _refreshMessages();
        return;
      case 'socket_disconnected':
        _resetTypingState();
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
      case 'coins_updated':
        final coins = data['coins'];
        if (coins is int) UserDataCache().updateCoins(coins);
        return;
    }
  }

  void _setPeerTyping(bool typing) =>
      TypingCache().setListenerTyping(widget.listenerId, typing);

  void _emitTyping(String text) {
    if (text.trim().isEmpty) {
      _stopTyping();
      return;
    }
    final now = DateTime.now();
    final last = _lastTypingSentAt;
    if (last == null || now.difference(last) >= const Duration(seconds: 1)) {
      _lastTypingSentAt = now;
      ChatSocketService().sendTyping(
        listenerId: widget.listenerId,
        isTyping: true,
      );
    }
    _typingSendTimer?.cancel();
    _typingSendTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    _typingSendTimer?.cancel();
    _typingSendTimer = null;
    if (_lastTypingSentAt == null) return;
    _lastTypingSentAt = null;
    ChatSocketService().sendTyping(
      listenerId: widget.listenerId,
      isTyping: false,
    );
  }

  void _resetTypingState() {
    _typingSendTimer?.cancel();
    _typingSendTimer = null;
    _lastTypingSentAt = null;
    TypingCache().clear();
  }

  bool _canAfford() {
    final coins = userCoinsNotifier.value;
    if (coins == null) return true;
    if (coins >= _chatMessageCoinCost) return true;
    _showInsufficientCoins();
    return false;
  }

  Future<void> _sendText(String text) async {
    final token = _token;
    if (token == null || !_canAfford()) return;
    _stopTyping();
    final clientId = const Uuid().v4();
    _merge([
      {
        'client_id': clientId,
        'listener_id': widget.listenerId,
        'sender_type': 'user',
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
    if (token == null || !_canAfford()) return;
    final clientId = const Uuid().v4();
    _merge([
      {
        'client_id': clientId,
        'listener_id': widget.listenerId,
        'sender_type': 'user',
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
        widget.listenerId,
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
        widget.listenerId,
        LocalChatMessage.fromJson(sent, widget.listenerId),
      );
    } on InsufficientCoinsException {
      if (!mounted) return;
      _removeMessage(clientId);
      _showInsufficientCoins();
      _refreshProfile();
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
        widget.listenerId,
        text,
        clientId: clientId,
      );
      await _chatStorage.removePending(clientId);
      await _chatStorage.upsertMessage(
        widget.listenerId,
        LocalChatMessage.fromJson(sent, widget.listenerId),
      );
      if (!mounted) return;
      _merge([sent]);
      _refreshProfile();
    } on InsufficientCoinsException {
      await _chatStorage.removePending(clientId);
      if (!mounted) return;
      _removeMessage(clientId);
      _showInsufficientCoins();
      _refreshProfile();
    } catch (_) {
      await _chatStorage.addPending(
        PendingMessage(
          clientId: clientId,
          otherId: widget.listenerId,
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

  void _showInsufficientCoins() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Not enough coins to send this message')),
    );
  }

  Future<void> _toggleFavorite() async {
    final token = _token;
    if (token == null) return;
    final next = !_favorite.value;
    _favorite.value = next;
    try {
      await _repository.updateChatSettings(
        token,
        widget.listenerId,
        isPinned: next,
      );
    } catch (_) {
      if (mounted) _favorite.value = !next;
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListenerProfileViewScreen(
          listenerId: widget.listenerId,
          initialName: widget.listenerName,
          initialPhotoUrl: widget.listenerPhotoUrl,
        ),
      ),
    );
  }

  Future<void> _callListener({bool video = false}) async {
    final token = _token;
    if (_callingListener || token == null) return;
    if (ActiveCallManager.instance.hasActiveCall) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are already on a call')),
      );
      return;
    }
    _callingListener = true;
    try {
      final result = await _repository.initiateCall(
        token,
        widget.listenerId,
        callType: video ? 'video' : 'audio',
      );
      if (!mounted) return;
      ActiveCallManager.instance.start(
        ActiveCallInfo(
          role: ActiveCallRole.user,
          callId: result['call_id'],
          otherPartyName: widget.listenerName,
          otherPartyPhotoUrl: widget.listenerPhotoUrl,
          isVideo: video,
          listenerId: widget.listenerId,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      _callingListener = false;
    }
  }

  Widget _subtitle() {
    return SizedBox(
      height: 16,
      child: ValueListenableBuilder<bool>(
        valueListenable: TypingCache().listener(widget.listenerId),
        builder: (context, typing, _) {
          return ValueListenableBuilder<bool?>(
            valueListenable: PresenceCache().listener(widget.listenerId),
            builder: (context, online, _) {
              if (typing) {
                return const Align(
                  alignment: Alignment.centerLeft,
                  child: TypingIndicator(color: _pink),
                );
              }
              if (online == null) return const SizedBox.shrink();
              return Text(
                online == true ? 'Online' : 'Offline',
                style: TextStyle(
                  color: online == true ? _green : Colors.white54,
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

  Widget _coinsPill({required bool isNarrow}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 14, vertical: 6),
      margin: EdgeInsets.only(right: isNarrow ? 6 : 12, left: 4),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on, color: Colors.amber, size: 16),
          const SizedBox(width: 6),
          ValueListenableBuilder<int?>(
            valueListenable: userCoinsNotifier,
            builder: (context, coins, _) => SizedBox(
              width: 34,
              child: Text(
                coins == null ? '' : '$coins',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 380;
    final isVeryNarrow = screenWidth < 340;
    final iconButtonStyle = IconButton.styleFrom(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 4 : 8),
      minimumSize: const Size(36, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: _bg,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 40,

        title: GestureDetector(
          onTap: _openProfile,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              AvatarImage(
                photoUrl: widget.listenerPhotoUrl,
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
                      widget.listenerName,
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
              Icons.call,
              color: Colors.white,
              size: isNarrow ? 20 : 24,
            ),
            onPressed: () => _callListener(),
          ),
          if (!isVeryNarrow)
            ValueListenableBuilder<bool>(
              valueListenable: _videoCallAvailable,
              builder: (context, available, _) => available
                  ? IconButton(
                      style: iconButtonStyle,
                      icon: Icon(
                        Icons.videocam,
                        color: Colors.white,
                        size: isNarrow ? 20 : 24,
                      ),
                      onPressed: () => _callListener(video: true),
                    )
                  : const SizedBox.shrink(),
            ),
          IconButton(
            style: iconButtonStyle,
            icon: Icon(
              Icons.card_giftcard,
              color: Colors.white,
              size: isNarrow ? 20 : 24,
            ),
            onPressed: () => showGiftSheet(
              context,
              listenerId: widget.listenerId,
              fromTop: true,
            ),
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
          _coinsPill(isNarrow: isNarrow),
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
                  isMine: (message) => message['sender_type'] == 'user',
                  giftCoins: (message) => (message['gift_coins'] ?? 0) as int,
                  otherPartyName: widget.listenerName,
                  chatKey: _chatKey,
                  liveMessageKeys: _liveMessageKeys,
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
            draftKey: _chatKey,
            maxLength: 100,
            tooLongMessage: 'Message too long, only 100 characters allowed',
            accentColor: _pink,
            backgroundColor: _bg,
          ),
        ],
      ),
    );
  }
}
