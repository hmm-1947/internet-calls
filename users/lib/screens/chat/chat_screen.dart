import 'dart:convert';
import 'dart:io';
import 'package:calls/widgets/voice_message_widget.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../core/api_endpoints.dart';
import '../../core/config.dart';
import '../../models/message.dart';
import '../../services/call_service.dart';

class ChatScreen extends StatefulWidget {
  final String myUsername;
  final String otherUsername;
  final CallService callService;

  const ChatScreen({
    super.key,
    required this.myUsername,
    required this.otherUsername,
    required this.callService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;

  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    widget.callService.addChatListener(_onIncomingMessage);
  }

  @override
  void dispose() {
    widget.callService.removeChatListener(_onIncomingMessage);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onIncomingMessage(String from, String content, String messageType) {
    if (from != widget.otherUsername) return;
    setState(() {
      _messages.add(
        Message(
          id: DateTime.now().millisecondsSinceEpoch,
          sender: from,
          receiver: widget.myUsername,
          content: content,
          createdAt: DateTime.now(),
          messageType: messageType,
        ),
      );
    });
    _scrollToBottom();
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() => _recording = false);
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.httpBase}/voice_messages'),
    );
    request.fields['sender'] = widget.myUsername;
    request.fields['receiver'] = widget.otherUsername;
    request.files.add(await http.MultipartFile.fromPath('file', path));

    final response = await request.send();
    if (response.statusCode == 200) {
      final body = await response.stream.bytesToString();
      final json = jsonDecode(body);
      setState(() {
        _messages.add(
          Message(
            id: json['id'],
            sender: json['sender'],
            receiver: json['receiver'],
            content: json['content'],
            createdAt: DateTime.parse(json['created_at']),
            messageType: 'voice',
          ),
        );
      });
      _scrollToBottom();
    }
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;
    final dir = await getTemporaryDirectory();
    _recordingPath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.aac';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _recordingPath!,
    );
    setState(() => _recording = true);
  }

  Future<void> _fetchMessages() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse(
          '${AppConfig.httpBase}${ApiEndpoints.messages}/${widget.myUsername}/${widget.otherUsername}',
        ),
      );
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        setState(() {
          _messages.clear();
          _messages.addAll(list.map((e) => Message.fromJson(e)));
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      print('fetchMessages error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    _controller.clear();

    final msg = Message(
      id: DateTime.now().millisecondsSinceEpoch,
      sender: widget.myUsername,
      receiver: widget.otherUsername,
      content: content,
      createdAt: DateTime.now(),
    );

    setState(() => _messages.add(msg));
    _scrollToBottom();

    widget.callService.sendChatMessage(widget.otherUsername, content);

    await http.post(
      Uri.parse('${AppConfig.httpBase}${ApiEndpoints.messages}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sender': widget.myUsername,
        'receiver': widget.otherUsername,
        'content': content,
      }),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.day} ${_monthName(dt.month)} ${dt.year}';
  }

  String _monthName(int m) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[m];
  }

  List<dynamic> _buildItems() {
    final items = <dynamic>[];
    String? lastLabel;
    for (final msg in _messages) {
      final label = _formatDateLabel(msg.createdAt.toLocal());
      if (label != lastLabel) {
        items.add(label);
        lastLabel = label;
      }
      items.add(msg);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        title: Text(
          widget.otherUsername,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF252533)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF3B6B)),
                  )
                : _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(color: Color(0xFF8888AA)),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];

                      if (item is String) {
                        return Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E2A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              item,
                              style: const TextStyle(
                                color: Color(0xFF8888AA),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }

                      final msg = item as Message;
                      final isMe = msg.sender == widget.myUsername;

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.72,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFFFF3B6B)
                                : const Color(0xFF1E1E2A),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isMe ? 16 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 16),
                            ),
                          ),
                          child: msg.messageType == 'voice'
                              ? VoiceMessageWidget(
                                  url:
                                      '${AppConfig.httpBase}/voice_messages/${msg.content}',
                                  isMe: isMe,
                                  sentAt: msg.createdAt,
                                )
                              : Stack(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 42,
                                        bottom: 2,
                                      ),
                                      child: Text(
                                        msg.content,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Text(
                                        _formatTime(msg.createdAt.toLocal()),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF13131A),
              border: Border(top: BorderSide(color: Color(0xFF252533))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(color: Color(0xFF8888AA)),
                      filled: true,
                      fillColor: const Color(0xFF1E1E2A),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTapDown: (_) => _startRecording(),
                  onTapUp: (_) => _stopRecording(),
                  onTapCancel: () => _stopRecording(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _recording ? Colors.red : const Color(0xFF1E1E2A),
                    ),
                    child: Icon(
                      _recording ? Icons.stop : Icons.mic,
                      color: _recording
                          ? Colors.white
                          : const Color(0xFF8888AA),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFF3B6B),
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
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
