import 'package:flutter/material.dart';
import 'package:livekitlistener/screens/calls/active_video_call_screen.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import 'navs/standby_tab.dart';
import 'navs/chat_tab.dart';
import 'navs/call_logs_tab.dart';
import 'navs/profile_tab.dart';
import 'calls/active_call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WebSocketService _wsService = WebSocketService();
  int _currentIndex = 0;
  String? _username;
  bool _incomingDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _wsService.connect();
    _wsService.events.listen(_handleEvent);
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    setState(() => _username = username);
  }

  void _showIncomingVideoCallDialog({
    required String from,
    required String room,
    required String token,
  }) {
    _incomingDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Incoming Video Call'),
        content: Text('$from is video calling you'),
        actions: [
          TextButton(
            onPressed: () {
              _wsService.send({'event': 'call_rejected', 'to': from});
              _incomingDialogOpen = false;
              Navigator.pop(context);
            },
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () {
              _incomingDialogOpen = false;
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ActiveVideoCallScreen(
                    room: room,
                    token: token,
                    callerName: from,
                    wsService: _wsService,
                  ),
                ),
              );
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    ).then((_) => _incomingDialogOpen = false);
  }

  void _handleEvent(Map<String, dynamic> message) {
    if (message['event'] == 'incoming_call') {
      _showIncomingCallDialog(
        from: message['from'] as String,
        room: message['room'] as String,
        token: message['token'] as String,
      );
    } else if (message['event'] == 'call_ended' && _incomingDialogOpen) {
      _incomingDialogOpen = false;
      if (mounted) Navigator.pop(context);
    } else if (message['event'] == 'incoming_video_call') {
      _showIncomingVideoCallDialog(
        from: message['from'] as String,
        room: message['room'] as String,
        token: message['token'] as String,
      );
    }
  }

  void _showIncomingCallDialog({
    required String from,
    required String room,
    required String token,
  }) {
    _incomingDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Incoming Call'),
        content: Text('$from is calling you'),
        actions: [
          TextButton(
            onPressed: () {
              _wsService.send({'event': 'call_rejected', 'to': from});
              _incomingDialogOpen = false;
              Navigator.pop(context);
            },
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () {
              _incomingDialogOpen = false;
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ActiveCallScreen(
                    room: room,
                    token: token,
                    callerName: from,
                    wsService: _wsService,
                  ),
                ),
              );
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    ).then((_) => _incomingDialogOpen = false);
  }

  Future<void> _logout() async {
    _wsService.disconnect();
    await AuthService.logout();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() {
    _wsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      StandbyTab(username: _username),
      ChatTab(wsService: _wsService),
      const CallLogsTab(),
      ProfileTab(username: _username, onLogout: _logout),
    ];

    return Scaffold(
      body: tabs[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Calls',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
