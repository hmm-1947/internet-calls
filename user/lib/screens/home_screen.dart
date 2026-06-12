import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import 'nav/listeners_tab.dart';
import 'nav/chat_tab.dart';
import 'nav/call_logs_tab.dart';
import 'nav/profile_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WebSocketService _wsService = WebSocketService();
  int _currentIndex = 0;
  String? _username;

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

  void _handleEvent(Map<String, dynamic> message) {
    final event = message['event'];
    if (event == 'call_rejected') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listener rejected the call')),
        );
      }
    }
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
      ListenersTab(wsService: _wsService),
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
