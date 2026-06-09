//listeners main_shell.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:listener/core/config.dart';
import 'package:listener/screens/calls/video_call_screen.dart';
import 'package:listener/services/fcm_service.dart';
import 'package:listener/services/video_call_services.dart';
import 'package:listener/widgets/incoming_video_call_dialog.dart';
import 'package:listener/widgets/video_pip_overlay.dart';
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

  const MainShell({super.key, required this.myUsername, required this.role});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  final _pipOverlay = VideoPipOverlay();
  late final CallService _callService;
  VideoCallService? _videoCallService;
  bool _pendingCallAccepted = false;
  bool _videoCallActive = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _callService = CallService(myUsername: widget.myUsername);
    _callService.onIncomingVideoCall = _handleIncomingVideoCall;
    _callService.addVideoSignalListener(_onVideoSignal);
    _callService.onIncomingCall = (callerName) async {
      if (!mounted) return;
      final accepted = await AppStorage.getPendingCallAccepted();
      if (accepted) {
        await AppStorage.clearPendingCallData();
        await _checkPendingCall(callerName);
      }
    };
    _callService.connect();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
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

  Future<void> _checkPendingCall(String callerName) async {
    await FCMService.cancelCallNotification();
    final res = await http.get(
      Uri.parse("${AppConfig.httpBase}/call/pending/${widget.myUsername}"),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data["pending"] == true) {
        _handlePendingIncomingCall(callerName);
      } else {
        await AppStorage.clearPendingCallData();
      }
    }
  }

  Future<void> _checkPendingVideoCall() async {
    final accepted = await AppStorage.getPendingVideoCallAccepted();
    if (!accepted) return;

    final caller = await AppStorage.getPendingVideoCaller();
    final sdp = await AppStorage.getPendingVideoSdp();

    if (caller == null || sdp == null) {
      await AppStorage.clearPendingVideoCallData();
      return;
    }

    await FCMService.cancelVideoCallNotification();
    await AppStorage.clearPendingVideoCallData();

    try {
      final res = await http.get(
        Uri.parse(
          "${AppConfig.httpBase}/call/video/pending/${widget.myUsername}",
        ),
      );
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      if (data["pending"] != true) return;
    } catch (_) {
      return;
    }

    await _waitForWsConnection();
    if (!mounted) return;

    final offerData = {'type': 'video_offer', 'sdp': sdp};
    _showIncomingVideoCallDialog(caller, offerData);
  }

  Future<void> _waitForWsConnection() async {
    int attempts = 0;
    while (!_callService.isConnected && attempts < 20) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }
  }

  void _handleIncomingVideoCall(
    String callerName,
    Map<String, dynamic> offerData,
  ) {
    if (!mounted) return;
    if (_videoCallActive) return;
    _showIncomingVideoCallDialog(callerName, offerData);
  }

  void _showIncomingVideoCallDialog(
    String callerName,
    Map<String, dynamic> offerData,
  ) {
    if (!mounted) return;
    if (_videoCallActive) {
      print('[DIALOG] blocked by _videoCallActive=true');
      return;
    }

    print('[DIALOG] showing for $callerName');
    _videoCallActive = true;
    _videoCallService?.dispose();
    _videoCallService = VideoCallService(callService: _callService);

    final svc = _videoCallService!;

    svc.onCallEnded = () {
      print('[DIALOG] onCallEnded fired');
      _pipOverlay.hide();
      _pipOverlay.disposeRenderer();
      _videoCallService = null;
      _videoCallActive = false;
      print('[DIALOG] _videoCallActive reset to false');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return IncomingVideoCallDialog(
          callerName: callerName,
          offerData: offerData,
          videoCallService: svc,
          pipOverlay: _pipOverlay,
          onReject: () {
            print('[DIALOG] rejected');
            Navigator.of(dialogContext).pop();
            _callService.sendSignal(callerName, {'type': 'video_hangup'});
            _callService.clearPendingVideoOffer();
            svc.dispose();
            _videoCallService = null;
            _videoCallActive = false;
            print('[DIALOG] _videoCallActive reset after reject');
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
        print('[SIGNAL] video_hangup received, resetting _videoCallActive');
        _videoCallService?.remoteHangup();
        break;
    }
  }

  void _handlePendingIncomingCall(String callerName) {
    if (!mounted) return;

    setState(() {
      _index = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _callService.acceptCall();

      if (!mounted || _callService.remoteUser == null) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveCallScreen(
            callService: _callService,
            remoteUser: _callService.remoteUser!,
          ),
        ),
      );
    });
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
        pipOverlay: _pipOverlay,
        getVideoCallService: () => _videoCallService,
        setVideoCallService: (svc) => setState(() => _videoCallService = svc),
        onShowVideoCallDialog: _showIncomingVideoCallDialog,
      ),
      ChatListScreen(myUsername: widget.myUsername, callService: _callService),
      const SizedBox(),
      LogsScreen(
        onCallUser: (_) {
          _switchTab(0);
        },
      ),
      ProfileScreen(username: widget.myUsername, role: widget.role),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF13131A),
          border: Border(top: BorderSide(color: Color(0xFF252533))),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.grid_view_rounded,
                  label: "Home",
                  selected: _index == 0,
                  onTap: () {
                    _switchTab(0);
                  },
                ),
                _NavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: "Chat",
                  selected: _index == 1,
                  onTap: () {
                    _switchTab(1);
                  },
                ),
                _NavItem(
                  icon: Icons.call_outlined,
                  label: "Calls",
                  selected: _index == 3,
                  onTap: () {
                    _switchTab(3);
                  },
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? const Color(0xFFFF3B6B)
                  : const Color(0xFF8888AA),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected
                    ? const Color(0xFFFF3B6B)
                    : const Color(0xFF8888AA),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
