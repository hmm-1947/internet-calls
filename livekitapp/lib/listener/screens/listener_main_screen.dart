import 'package:flutter/material.dart';
import 'package:livekitapp/listener/screens/listener_call_history_screen.dart';
import 'package:livekitapp/listener/screens/listener_home_screen.dart';
import 'package:livekitapp/listener/screens/listener_chats_list_screen.dart';
import 'package:livekitapp/listener/screens/listener_settings_screen.dart';
import 'package:livekitapp/main_listener.dart';
import 'package:livekitapp/shared/widgets/crown_nav_bar.dart';

class ListenerMainScreen extends StatefulWidget {
  const ListenerMainScreen({super.key});

  @override
  State<ListenerMainScreen> createState() => _ListenerMainScreenState();
}

class _ListenerMainScreenState extends State<ListenerMainScreen> {
  int _index = 0;
  final _settingsKey = GlobalKey<ListenerSettingsScreenState>();

  late final List<Widget> _screens = [
    const ListenerHomeScreen(),
    const ListenerChatsListScreen(),
    const ListenerCallHistoryScreen(),
    ListenerSettingsScreen(key: _settingsKey),
  ];
  void _onDestinationSelected(int i) {
    setState(() => _index = i);
    if (i == 1) {
      chatMessageNotifier.value = 0;
    }
    if (i == 3) {
      _settingsKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: CrownNavBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        onCrownTap: () {},
        showCrown: false,
        labels: const ['Home', 'Chat', 'Calls', 'Settings'],
        icons: [
          const Icon(Icons.grid_view_rounded),
          ValueListenableBuilder<int>(
            valueListenable: chatMessageNotifier,
            builder: (context, count, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble_outline),
                if (count > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.call_outlined),
          const Icon(Icons.settings_outlined),
        ],
      ),
    );
  }
}
