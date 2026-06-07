import 'package:flutter/material.dart';
import 'package:listener/screens/calls/video_call_screen.dart';
import 'package:listener/services/video_call_services.dart';
import 'package:listener/widgets/incoming_video_call_dialog.dart';

import '../core/storage.dart';
import '../services/call_service.dart';
import 'calls/call_tab.dart';
import 'calls/logs_screen.dart';
import 'calls/active_call_screen.dart';
import 'profile/profile_screen.dart';
import 'chat/chat_list_screen.dart';

class MainShell extends StatefulWidget {
  final String myUsername;
  final String role;

  const MainShell({
    
    super.key,
    required this.myUsername,
    required this.role,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with WidgetsBindingObserver {
  int _index = 0;

  late final CallService _callService;
  VideoCallService? _videoCallService;
  bool _pendingCallAccepted = false;

  @override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _callService = CallService(myUsername: widget.myUsername);
  _callService.onIncomingVideoCall = _handleIncomingVideoCall;
  _callService.addVideoSignalListener(_onVideoSignal);
  _checkPendingCall();
}

  @override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _callService.removeVideoSignalListener(_onVideoSignal);
  _callService.dispose();
  _videoCallService?.dispose();
  super.dispose();
}

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _callService.disconnect();
    }

    if (state == AppLifecycleState.resumed) {
      if (!_callService.isConnected) {
        _callService.connect();
      }
    }
  }

  Future<void> _checkPendingCall() async {
    final accepted =
        await AppStorage.getPendingCallAccepted();

    if (!accepted) {
      return;
    }

    await AppStorage.clearPendingCallData();

    _pendingCallAccepted = true;
  }

  void _handleIncomingVideoCall(String callerName, Map<String, dynamic> offerData) {
  if (!mounted) return;

  _videoCallService = VideoCallService(callService: _callService);

  bool dialogDismissed = false;

  _videoCallService!.onCallEnded = () {
    if (!dialogDismissed) {
      dialogDismissed = true;
      if (mounted) Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst || route.settings.name != null);
    }
    _videoCallService?.dispose();
    _videoCallService = null;
  };

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      _videoCallService!.onCallEnded = () {
        dialogDismissed = true;
        if (mounted) Navigator.of(dialogContext).pop();
        _videoCallService?.dispose();
        _videoCallService = null;
      };
      return IncomingVideoCallDialog(
        callerName: callerName,
        offerData: offerData,
        videoCallService: _videoCallService!,
        onReject: () {
          dialogDismissed = true;
          Navigator.of(dialogContext).pop();
          _callService.sendSignal(callerName, {'type': 'video_hangup'});
          _callService.clearPendingVideoOffer();
          _videoCallService?.dispose();
          _videoCallService = null;
        },
      );
    },
  );
}

void _onVideoSignal(String type, Map<String, dynamic> data, String? from) {
  switch (type) {
    case 'video_answer':
      _videoCallService?.handleAnswer(data);
      break;
    case 'video_candidate':
      _videoCallService?.handleCandidate(data);
      break;
    case 'video_hangup':
      _videoCallService?.remoteHangup();
      _videoCallService?.dispose();
      _videoCallService = null;
      break;
  }
}
  void _handlePendingIncomingCall(
    String callerName,
  ) {
    if (!_pendingCallAccepted) {
      return;
    }

    _pendingCallAccepted = false;

    if (!mounted) {
      return;
    }

    setState(() {
      _index = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        await _callService.acceptCall();

        if (!mounted ||
            _callService.remoteUser == null) {
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveCallScreen(
              callService: _callService,
              remoteUser:
                  _callService.remoteUser!,
            ),
          ),
        );
      },
    );
  }

  void _switchTab(int index) {
    setState(() {
      _index = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      CallTab(
        myUsername: widget.myUsername,
        callService: _callService,
        onIncomingCallReady:
            _pendingCallAccepted
                ? _handlePendingIncomingCall
                : null,
      ),
      ChatListScreen(
        myUsername: widget.myUsername,
        callService: _callService,
      ),
      const SizedBox(),
      LogsScreen(
        onCallUser: (_) {
          _switchTab(0);
        },
      ),
      ProfileScreen(username: widget.myUsername, role:widget.role),
    ];

    return Scaffold(
      backgroundColor: const Color(
        0xFF0A0A0F,
      ),
      body: IndexedStack(
        index: _index,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF13131A),
          border: Border(
            top: BorderSide(
              color: Color(0xFF252533),
            ),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon:
                      Icons.grid_view_rounded,
                  label: "Home",
                  selected: _index == 0,
                  onTap: () {
                    _switchTab(0);
                  },
                ),
                _NavItem(
                  icon: Icons
                      .chat_bubble_outline_rounded,
                  label: "Chat",
                  selected: _index == 1,
                  onTap: () {
                    _switchTab(1);
                  },
                ),
                _NavItem(
                  icon:
                      Icons.call_outlined,
                  label: "Calls",
                  selected: _index == 3,
                  onTap: () {
                    _switchTab(3);
                  },
                ),
                _NavItem(
                  icon: Icons
                      .person_outline_rounded,
                  label: "Profile",
                  selected: _index == 4,
                  onTap: () {
                    _switchTab(4);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? const Color(
                      0xFFFF3B6B,
                    )
                  : const Color(
                      0xFF8888AA,
                    ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected
                    ? const Color(
                        0xFFFF3B6B,
                      )
                    : const Color(
                        0xFF8888AA,
                      ),
                fontWeight: selected
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}