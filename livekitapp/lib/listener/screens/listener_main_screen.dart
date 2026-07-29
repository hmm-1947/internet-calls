import 'package:flutter/material.dart';
import 'package:livekitapp/listener/screens/calls/listener_call_history_screen.dart';
import 'package:livekitapp/listener/screens/listener_home_screen.dart';
import 'package:livekitapp/listener/screens/chats/listener_chats_list_screen.dart';
import 'package:livekitapp/listener/screens/listener_settings_screen.dart';
import 'package:livekitapp/listener/screens/weekly_challenge_screen.dart';
import 'package:livekitapp/listener/repository/weekly_challenge_repository.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/main_listener.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/crown_nav_bar.dart';
import 'package:livekitapp/common/widgets/faded_indexed_stack.dart';

class ListenerMainScreen extends StatefulWidget {
  const ListenerMainScreen({super.key});

  @override
  State<ListenerMainScreen> createState() => _ListenerMainScreenState();
}

class _ListenerMainScreenState extends State<ListenerMainScreen> {
  int _index = 0;
  final _settingsKey = GlobalKey<ListenerSettingsScreenState>();
  final _weeklyChallengeRepository = WeeklyChallengeRepository();
  final _localStorage = LocalStorage();
  bool _weeklyChallengeActive = false;

  late final List<Widget> _screens = [
    ListenerHomeScreen(onRefresh: _refreshWeeklyChallengeStatus),
    const ListenerChatsListScreen(),
    const ListenerCallHistoryScreen(),
    ListenerSettingsScreen(key: _settingsKey),
  ];

  @override
  void initState() {
    super.initState();
    _refreshWeeklyChallengeStatus();
  }

  Future<void> _refreshWeeklyChallengeStatus() async {
    try {
      final token = await _localStorage.getToken();
      if (token == null) return;
      final progress = await _weeklyChallengeRepository.getProgress(token);
      if (!mounted) return;
      setState(() => _weeklyChallengeActive = progress.active);
    } catch (_) {
      // If the check fails, keep the icon hidden rather than risk showing
      // it for an expired/non-existent challenge.
      if (mounted) setState(() => _weeklyChallengeActive = false);
    }
  }

  void _onDestinationSelected(int i) {
    setState(() => _index = i);
    if (i == 1) {
      chatMessageNotifier.value = 0;
    }
    if (i == 3) {
      _settingsKey.currentState?.refresh();
    }
    if (i == 0) {
      _refreshWeeklyChallengeStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final navBarHeight = 78 + bottomInset;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          FadedIndexedStack(index: _index, children: _screens),
          if (_index == 0 && _weeklyChallengeActive)
            Positioned(
              right: 16,
              bottom: navBarHeight + 16,
              child: _WeeklyChallengeFab(
                onTap: () async {
                  await Navigator.of(
                    context,
                  ).push(fadeRoute(const WeeklyChallengeScreen()));
                  _refreshWeeklyChallengeStatus();
                },
              ),
            ),
        ],
      ),

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

class _WeeklyChallengeFab extends StatelessWidget {
  final VoidCallback onTap;

  const _WeeklyChallengeFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFE53950),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE53950).withOpacity(0.55),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.emoji_events, color: Colors.white, size: 26),
      ),
    );
  }
}

