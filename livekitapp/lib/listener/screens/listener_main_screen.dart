import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import 'package:livekitapp/common/widgets/auto_hide_nav_bar.dart';
import 'package:livekitapp/common/widgets/keep_alive_page.dart';
import 'package:livekitapp/common/widgets/listener_home_header.dart';

class ListenerMainScreen extends StatefulWidget {
  const ListenerMainScreen({super.key});
//test
  @override
  State<ListenerMainScreen> createState() => _ListenerMainScreenState();
}

class _ListenerMainScreenState extends State<ListenerMainScreen> {
  int _index = 0;
  bool _navBarVisible = true;

  /// Tabs that have reported a vertical scrollable with somewhere to go. A tab
  /// that is not in here cannot scroll, so it has no way of bringing a hidden
  /// nav bar back on its own and gets it back automatically instead.
  final Set<int> _scrollablePages = {};

  final _settingsKey = GlobalKey<ListenerSettingsScreenState>();
  final _homeKey = GlobalKey<ListenerHomeScreenState>();
  final _weeklyChallengeRepository = WeeklyChallengeRepository();
  final _localStorage = LocalStorage();
  bool _weeklyChallengeActive = false;
  late final PageController _pageController = PageController(
    initialPage: _index,
  );

  bool _onScrollNotification(int index, ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (!_recordScrollability(index, metrics)) return false;
    if (notification is ScrollUpdateNotification) {
      if (metrics.pixels <= metrics.minScrollExtent) {
        _showNavBar();
        return false;
      }
      final delta = notification.scrollDelta ?? 0;
      if (delta.abs() < 1) return false;
      if (delta > 0 && _navBarVisible) {
        setState(() => _navBarVisible = false);
      } else if (delta < 0 && !_navBarVisible) {
        setState(() => _navBarVisible = true);
      }
    }
    return false;
  }

  /// Content dimensions arrive here without the user touching anything, which
  /// is what tells us a tab has become (or stopped being) scrollable.
  bool _onScrollMetrics(int index, ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis == Axis.vertical) _recordScrollability(index, metrics);
    return false;
  }

  /// Returns whether the tab can actually be scrolled, and reveals the nav bar
  /// when the tab the user is looking at cannot.
  bool _recordScrollability(int index, ScrollMetrics metrics) {
    final canScroll =
        metrics.hasContentDimensions &&
        metrics.maxScrollExtent > metrics.minScrollExtent;
    if (canScroll) {
      _scrollablePages.add(index);
      return true;
    }
    _scrollablePages.remove(index);
    if (index == _index) _showNavBar();
    return false;
  }

  /// Brings a hidden nav bar back when moving to a tab that cannot scroll.
  void _revealNavBarForPage(int index) {
    if (_scrollablePages.contains(index)) return;
    _showNavBar();
  }

  void _showNavBar() {
    if (_navBarVisible) return;
    // Scroll metrics land mid-frame, so the rebuild is deferred when it would
    // otherwise happen during build or layout.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNavBar();
      });
      return;
    }
    setState(() => _navBarVisible = true);
  }

  late final List<Widget> _screens = [
    ListenerHomeScreen(
      key: _homeKey,
      onRefresh: _refreshWeeklyChallengeStatus,
    ),
    const ListenerChatsListScreen(),
    const ListenerCallHistoryScreen(),
    ListenerSettingsScreen(key: _settingsKey),
  ];

  @override
  void initState() {
    super.initState();
    _refreshWeeklyChallengeStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

  void _onTabSelected(int i) {
    if (i == _index) return;
    _revealNavBarForPage(i);
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    _revealNavBarForPage(i);
    if (i == 1) {
      chatMessageNotifier.value = 0;
    }
    if (i == 3) {
      _settingsKey.currentState?.refresh();
    }
    if (i == 0) {
      _homeKey.currentState?.refresh();
      _refreshWeeklyChallengeStatus();
    }
  }

  static const _titles = ['Home', 'Chats', 'Calls', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final navBarHeight = 78 + bottomInset;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      body: Column(
        children: [
          Container(
            color: Colors.black,
            child: SafeArea(
              bottom: false,
              child: ListenerHomeHeader(
                title: _titles[_index],
                isHome: _index == 0,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                // Listened to per page rather than around the whole PageView,
                // so a notification can be attributed to the tab it came from.
                PageView(
                  controller: _pageController,
                  physics: const ClampingScrollPhysics(),
                  onPageChanged: _onPageChanged,
                  children: [
                    for (var i = 0; i < _screens.length; i++)
                      KeepAlivePage(
                        child: RepaintBoundary(
                          child: NotificationListener<ScrollMetricsNotification>(
                            onNotification: (n) => _onScrollMetrics(i, n),
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (n) =>
                                  _onScrollNotification(i, n),
                              child: _screens[i],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

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
          ),
        ],
      ),

      bottomNavigationBar: AutoHideNavBar(
        visible: _navBarVisible,
        child: CrownNavBar(
          selectedIndex: _index,
          onDestinationSelected: _onTabSelected,
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

