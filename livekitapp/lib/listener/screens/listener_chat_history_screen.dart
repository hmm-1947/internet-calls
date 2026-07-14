import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/voice_message_bubble.dart';
import 'package:livekitapp/common/widgets/voice_record_button.dart';
import 'package:livekitapp/common/widgets/voice_recording_indicator.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/chat_storage.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/listener_call_notes_screen.dart';
import 'package:uuid/uuid.dart';

class ListenerChatHistoryScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const ListenerChatHistoryScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ListenerChatHistoryScreen> createState() =>
      _ListenerChatHistoryScreenState();
}

class _ListenerChatHistoryScreenState extends State<ListenerChatHistoryScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  final _chatStorage = ChatStorage();
  final _controller = TextEditingController();
  bool _hasText = false;
  final _scrollController = ScrollController();
  bool _isRecordingVoice = false;
  bool _isLocked = false;
  Duration _recordElapsed = Duration.zero;
  double _recordAmplitude = 0;
  List<Map<String, dynamic>> _messages = [];
  String? _token;
  StreamSubscription? _socketSub;
  bool _userTyping = false;
  bool _isUserOnline = false;
  Timer? _typingSendTimer;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _token = await _localStorage.getToken();
    await _load();
    _loadFavoriteStatus();
    ChatSocketService().connect(_token!, 'listener');
    _socketSub = ChatSocketService().stream.listen(_onSocketMessage);
    _controller.addListener(_onTyping);
    await _flushPending();
  }

  Future<void> _loadFavoriteStatus() async {
    if (_token == null) return;
    final threads = await _repository.getChatThreads(_token!);
    final thread = threads.firstWhere(
      (t) => t['user_id'] == widget.userId,
      orElse: () => {},
    );
    if (mounted) {
      setState(() {
        _isFavorite = thread['is_pinned'] ?? false;
        _isUserOnline = thread['is_online'] == true;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    if (_token == null) return;
    setState(() => _isFavorite = !_isFavorite);
    await _repository.updateChatSettings(
      _token!,
      widget.userId,
      isPinned: _isFavorite,
    );
  }

  void _onTyping() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
    ChatSocketService().sendTyping(userId: widget.userId, isTyping: true);
    _typingSendTimer?.cancel();
    _typingSendTimer = Timer(const Duration(seconds: 2), () {
      ChatSocketService().sendTyping(userId: widget.userId, isTyping: false);
    });
  }

  void _onVoiceStateChanged(
    bool recording,
    Duration elapsed,
    double amplitude,
  ) {
    setState(() {
      _isRecordingVoice = recording;
      _recordElapsed = elapsed;
      _recordAmplitude = amplitude;
    });
  }

  void _onLockChanged(bool locked) {
    setState(() => _isLocked = locked);
  }

  Future<void> _flushPending() async {
    final pending = await _chatStorage.getPending();
    for (final p in pending.where((p) => p.otherId == widget.userId)) {
      await _retrySend(p.clientId, p.message);
    }
  }

  void _onSocketMessage(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'chat_message' && data['user_id'] == widget.userId) {
      setState(() => _messages.add(data));
      _scrollToBottom();
      if (data['sender_type'] == 'user' && _token != null) {
        _repository.markMessagesRead(_token!, widget.userId);
      }
    } else if (type == 'typing' && data['user_id'] == widget.userId) {
      setState(() => _userTyping = data['is_typing'] == true);
    } else if ((type == 'user_online' || type == 'user_offline') &&
        data['user_id'] == widget.userId) {
      setState(() => _isUserOnline = type == 'user_online');
    } else if (type == 'message_status') {
      setState(() {
        final idx = _messages.indexWhere(
          (m) => m['client_id'] == data['client_id'],
        );
        if (idx != -1) _messages[idx]['status'] = data['status'];
      });
    } else if (type == 'read_receipt' && data['user_id'] == widget.userId) {
      setState(() {
        final ids = List<int>.from(data['message_ids'] ?? []);
        for (final m in _messages) {
          if (ids.contains(m['id'])) {
            m['status'] = 'read';
            m['is_read'] = true;
          }
        }
      });
    } else if (type == 'message_edited') {
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == data['id']);
        if (idx != -1) _messages[idx] = data;
      });
    } else if (type == 'message_deleted') {
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == data['id']);
        if (idx != -1) {
          _messages[idx]['is_deleted'] = true;
          _messages[idx]['message'] = '';
        }
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _load() async {
    if (_token == null) return;
    try {
      final messages = await _repository.getChatMessages(
        _token!,
        widget.userId,
      );
      if (mounted) {
        setState(() => _messages = messages);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _token == null) return;
    _controller.clear();
    final clientId = const Uuid().v4();
    setState(() {
      _messages.add({
        'client_id': clientId,
        'user_id': widget.userId,
        'sender_type': 'listener',
        'message': text,
        'status': 'sending',
        'is_deleted': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _scrollToBottom();
    await _retrySend(clientId, text);
  }

  String _fmtDateLabel(String iso) {
    final d = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      const days = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return days[d.weekday - 1];
    }
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _fmtMsgTime(String iso) {
    final local = DateTime.parse(iso).toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Future<void> _sendVoice(String filePath, int duration) async {
    if (_token == null) return;
    final clientId = const Uuid().v4();
    setState(() {
      _messages.add({
        'client_id': clientId,
        'user_id': widget.userId,
        'sender_type': 'listener',
        'message': '',
        'message_type': 'audio',
        'audio_url': filePath,
        'audio_duration': duration,
        'status': 'sending',
        'is_deleted': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _scrollToBottom();
    try {
      await _repository.sendVoiceMessage(
        _token!,
        widget.userId,
        filePath,
        duration,
        clientId: clientId,
      );
      await _load();
    } catch (_) {
      setState(() {
        final idx = _messages.indexWhere((m) => m['client_id'] == clientId);
        if (idx != -1) _messages[idx]['status'] = 'failed';
      });
    }
  }

  Future<void> _retrySend(String clientId, String text) async {
    try {
      await _repository.sendChatMessage(
        _token!,
        widget.userId,
        text,
        clientId: clientId,
      );
      await _chatStorage.removePending(clientId);
      await _load();
    } catch (_) {
      setState(() {
        final idx = _messages.indexWhere((m) => m['client_id'] == clientId);
        if (idx != -1) _messages[idx]['status'] = 'failed';
      });
      await _chatStorage.addPending(
        PendingMessage(
          clientId: clientId,
          otherId: widget.userId,
          message: text,
        ),
      );
      Future.delayed(
        const Duration(seconds: 5),
        () => _retrySend(clientId, text),
      );
    }
  }

  Widget _statusIcon(String? status) {
    IconData icon;
    Color color = Colors.white70;
    switch (status) {
      case 'sending':
      case 'queued':
        icon = Icons.access_time;
        break;
      case 'sent':
        icon = Icons.check;
        break;
      case 'delivered':
        icon = Icons.done_all;
        break;
      case 'read':
        icon = Icons.done_all;
        color = Colors.lightBlueAccent;
        break;
      case 'failed':
        icon = Icons.error_outline;
        color = Colors.redAccent;
        break;
      default:
        icon = Icons.check;
    }
    return Icon(icon, size: 14, color: color);
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _typingSendTimer?.cancel();
    _controller.removeListener(_onTyping);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0B0F1A);
    const bubbleIn = Color(0xFF1F2430);
    const bubbleOut = Color(0xFF7A1620);
    const pink = Color(0xFFE53950);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFF2A3145),
              child: Icon(Icons.person, color: Colors.white54),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.userName,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  _userTyping
                      ? 'typing...'
                      : (_isUserOnline ? 'Online' : 'Offline'),
                  style: TextStyle(
                    color: _userTyping
                        ? const Color(0xFFE53950)
                        : (_isUserOnline
                              ? const Color(0xFF74D8BD)
                              : Colors.white54),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.note_alt_outlined, color: Colors.white),
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
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? const Color(0xFFE53950) : Colors.white,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['sender_type'] == 'listener';
                final showDateHeader =
                    index == 0 ||
                    _fmtDateLabel(_messages[index]['created_at']) !=
                        _fmtDateLabel(_messages[index - 1]['created_at']);
                final bubble = Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 56),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 2,
                      top: 8,
                      bottom: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? bubbleOut : bubbleIn,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 52, bottom: 14),
                          child: msg['is_deleted'] == true
                              ? Text(
                                  'Message deleted',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : msg['message_type'] == 'audio'
                              ? VoiceMessageBubble(
                                  audioUrl: msg['audio_url'] ?? '',
                                  durationSeconds: msg['audio_duration'] ?? 0,
                                  isMe: isMe,
                                  createdAt: DateTime.parse(msg['created_at']),
                                )
                              : Text(
                                  msg['message'],
                                  style: const TextStyle(color: Colors.white),
                                ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _fmtMsgTime(msg['created_at']),
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.black54,
                                  fontSize: 11,
                                ),
                              ),
                              if (isMe) const SizedBox(width: 4),
                              if (isMe) _statusIcon(msg['status']),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                if (!showDateHeader) return bubble;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2430),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _fmtDateLabel(msg['created_at']),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    bubble,
                  ],
                );
              },
            ),
          ),
          if (_userTyping)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'typing...',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            ),
          Container(
            color: bg,
            padding: EdgeInsets.fromLTRB(
              8,
              8,
              8,
              8 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2032),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: _isRecordingVoice
                            ? VoiceRecordingIndicator(
                                elapsed: _recordElapsed,
                                amplitude: _recordAmplitude,
                              )
                            : TextField(
                                controller: _controller,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  hintText: 'Type a message',
                                  hintStyle: TextStyle(color: Colors.white54),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_hasText)
                      Container(
                        decoration: const BoxDecoration(
                          color: pink,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _send,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: VoiceRecordButton(
                          onRecorded: _sendVoice,
                          onStateChanged: _onVoiceStateChanged,
                          onLockChanged: _onLockChanged,
                          idleColor: pink,
                        ),
                      ),
                  ],
                ),
                if (_isLocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () =>
                              VoiceRecordButton.currentState?.triggerCancel(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.pause, color: Colors.blue),
                          onPressed: () =>
                              VoiceRecordButton.currentState?.triggerPause(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colors.blue),
                          onPressed: () =>
                              VoiceRecordButton.currentState?.triggerSend(),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
