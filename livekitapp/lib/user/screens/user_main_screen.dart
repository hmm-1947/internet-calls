import 'package:flutter/material.dart';
import 'package:livekitapp/main_user.dart';
import 'package:livekitapp/shared/widgets/crown_nav_bar.dart';
import 'package:livekitapp/user/screens/user_home_screen.dart';
import 'package:livekitapp/user/screens/chats_list_screen.dart';
import 'package:livekitapp/user/screens/user_profile_screen.dart';
import 'package:livekitapp/user/screens/calls/call_history_screen.dart';
import 'package:livekitapp/user/screens/upgrade_screen.dart';
import 'package:livekitapp/shared/widgets/faded_indexed_stack.dart';
import 'package:livekitapp/shared/utils/fade_page_route.dart';

class UserMainScreen extends StatefulWidget {
  const UserMainScreen({super.key});

  @override
  State<UserMainScreen> createState() => _UserMainScreenState();
}

class _UserMainScreenState extends State<UserMainScreen> {
  int _index = 0;
  final _profileKey = GlobalKey<UserProfileScreenState>();

  late final List<Widget> _screens = [
    const UserHomeScreen(),
    const ChatsListScreen(),
    const CallHistoryScreen(),
    UserProfileScreen(key: _profileKey),
  ];

  void _onDestinationSelected(int i) {
    setState(() => _index = i);
    if (i == 1) {
      userChatDotNotifier.value = false;
    }
    if (i == 3) {
      _profileKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A2E),
      extendBody: true,
      body: FadedIndexedStack(index: _index, children: _screens),
      bottomNavigationBar: CrownNavBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        onCrownTap: () {
          Navigator.of(context).push(fadeRoute(const UpgradeScreen()));
        },
        labels: const ['Home', 'Chat', 'Calls', 'Profile'],
        icons: [
          const Icon(Icons.grid_view_rounded),
          ValueListenableBuilder<bool>(
            valueListenable: userChatDotNotifier,
            builder: (context, hasDot, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble_outline),
                if (hasDot)
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
          const Icon(Icons.person_outline),
        ],
      ),
    );
  }
}
