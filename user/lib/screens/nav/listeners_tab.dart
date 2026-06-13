import 'package:flutter/material.dart';
import 'package:livekitcalls/screens/calls/active_call_screen.dart';
import 'package:livekitcalls/screens/calls/active_video_call_screen.dart';
import 'package:livekitcalls/screens/chat/chat_screen.dart';
import 'package:livekitcalls/services/auth_service.dart';
import 'package:livekitcalls/services/chat_service.dart';
import 'package:livekitcalls/services/coin_service.dart';
import '../../services/livekit_service.dart';
import '../../services/websocket_service.dart';

class ListenersTab extends StatefulWidget {
  final WebSocketService wsService;
  const ListenersTab({super.key, required this.wsService});

  @override
  State<ListenersTab> createState() => _ListenersTabState();
}

class _ListenersTabState extends State<ListenersTab> {
  List<String> _listeners = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchListeners();
    widget.wsService.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> message) {
    final event = message['event'];
    if (event == 'call_accepted') {
      // handled in active_call_screen
    }
  }

  Future<void> _fetchListeners() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listeners = await LiveKitService.getOnlineListeners();
      setState(() => _listeners = listeners);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _startChat(String listenerUsername) async {
    try {
      final conversationId = await ChatService.startChat(listenerUsername);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            partnerName: listenerUsername,
            wsService: widget.wsService,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _startCall(String listenerUsername) async {
  try {
    final token = await AuthService.getToken();
    final eligible = await CoinService.canCall(token!);
    if (!eligible) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Insufficient coins to make a call')),
        );
      }
      return;
    }
    final data = await LiveKitService.getToken(listenerUsername);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveCallScreen(
          room: data['room']!,
          token: data['token']!,
          listenerName: listenerUsername,
          wsService: widget.wsService,
        ),
      ),
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

  Future<void> _startVideoCall(String listenerUsername) async {
  try {
    final token = await AuthService.getToken();
    final eligible = await CoinService.canCall(token!);
    if (!eligible) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Insufficient coins to make a video call')),
        );
      }
      return;
    }
    final data = await LiveKitService.getVideoToken(listenerUsername);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveVideoCallScreen(
          room: data['room']!,
          token: data['token']!,
          listenerName: listenerUsername,
          wsService: widget.wsService,
        ),
      ),
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listeners'),
        actions: [
          IconButton(
            onPressed: _fetchListeners,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _listeners.isEmpty
          ? const Center(child: Text('No listeners online'))
          : ListView.builder(
              itemCount: _listeners.length,
              itemBuilder: (context, index) {
                final listener = _listeners[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.headset)),
                  title: Text(listener),
                  subtitle: const Text('Online'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _startChat(listener),
                        icon: const Icon(
                          Icons.chat_bubble,
                          color: Colors.green,
                        ),
                        tooltip: 'Chat',
                      ),
                      IconButton(
                        onPressed: () => _startVideoCall(listener),
                        icon: const Icon(Icons.videocam, color: Colors.blue),
                        tooltip: 'Video Call',
                      ),
                      FilledButton.icon(
                        onPressed: () => _startCall(listener),
                        icon: const Icon(Icons.call),
                        label: const Text('Call'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
