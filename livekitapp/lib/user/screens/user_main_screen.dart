import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/home_header.dart';
import 'package:livekitapp/core/network/user_data_cache.dart';
import 'package:livekitapp/main_user.dart';
import 'package:livekitapp/common/widgets/crown_nav_bar.dart';
import 'package:livekitapp/common/widgets/auto_hide_nav_bar.dart';
import 'package:livekitapp/common/widgets/keep_alive_page.dart';
import 'package:livekitapp/user/screens/user_home_screen.dart';
import 'package:livekitapp/user/screens/chats_list_screen.dart';
import 'package:livekitapp/user/screens/user_settings_screen.dart';
import 'package:livekitapp/user/screens/calls/call_history_screen.dart';
import 'package:livekitapp/user/screens/upgrade_screen.dart';

class UserMainScreen extends StatefulWidget {
  const UserMainScreen({super.key});

  @override
  State<UserMainScreen> createState() => _UserMainScreenState();
}

class _UserMainScreenState extends State<UserMainScreen> {
  int _index = 0;
  bool _navBarVisible = true;

  /// Tabs that have reported a vertical scrollable with somewhere to go. A tab
  /// that is not in here cannot scroll, so it has no way of bringing a hidden
  /// nav bar back on its own and gets it back automatically instead.
  final Set<int> _scrollablePages = {};

  final _profileKey = GlobalKey<UserProfileScreenState>();
  final _homeKey = GlobalKey<UserHomeScreenState>();
  late final PageController _pageController = PageController(
    initialPage: _index,
  );

  bool _onScrollNotification(int index, ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (!_recordScrollability(index, metrics)) return false;
    if (notification is ScrollUpdateNotification) {
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
    UserHomeScreen(key: _homeKey),
    const ChatsListScreen(),
    const CallHistoryScreen(),
    UserProfileScreen(key: _profileKey),
  ];

  static const _titles = ['', 'Chats', 'Calls', 'Settings'];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    if (i == 0) {
      _homeKey.currentState?.refresh();
    }
    if (i == 1) {
      userChatDotNotifier.value = false;
    }
    if (i == 3) {
      _profileKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Not on the home tab: back button just takes the user home
        // instead of exiting the app.
        _onTabSelected(0);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1A2E),
        extendBody: true,
        body: Column(
          children: [
            Container(
              color: Colors.black,
              child: SafeArea(
                bottom: false,
                child: ValueListenableBuilder<int?>(
                  valueListenable: userCoinsNotifier,
                  builder: (context, coins, _) => HomeHeader(
                    coins: coins,
                    title: _titles[_index],
                    isHome: _index == 0,
                  ),
                ),
              ),
            ),
            Expanded(
              // Listened to per page rather than around the whole PageView, so a
              // notification can be attributed to the tab it came from.
              child: PageView(
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
                            onNotification: (n) => _onScrollNotification(i, n),
                            child: _screens[i],
                          ),
                        ),
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
            crownImageAsset: 'assets/images/rupee_icon.png',
            crownSize: 85,
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
              const Icon(Icons.settings_outlined),
            ],
          ),
        ),
      ),
    );
  }
}
