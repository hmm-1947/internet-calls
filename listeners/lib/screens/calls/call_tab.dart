//listeners calltab.dart
import 'dart:convert';
import 'package:listener/core/config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:listener/core/config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:listener/core/config.dart';
import 'package:listener/services/fcm_service.dart';
import 'package:listener/core/storage.dart';
import 'package:listener/services/video_call_services.dart';
import 'package:listener/widgets/incoming_video_call_dialog.dart';
import 'package:listener/widgets/video_pip_overlay.dart';
import '../chat/chat_screen.dart';
import '../../models/call_log.dart';
import '../../services/call_log_store.dart';
import '../../services/call_service.dart';
import '../../widgets/incoming_call_dialog.dart';

import '../../widgets/user_tile.dart';
import 'active_call_screen.dart';

const _bg = Color(0xFF0A0A0F);
const _surface = Color(0xFF13131A);
const _border = Color(0xFF252533);
const _accent = Color(0xFFFF3B6B);
const _green = Color(0xFF22C55E);
const _textPrimary = Colors.white;
const _textSecondary = Color(0xFF8888AA);

class CallTab extends StatefulWidget {
  final String myUsername;
  final CallService callService;
  final void Function(String callerName)? onIncomingCallReady;
  final VideoPipOverlay pipOverlay;
  final VideoCallService? Function()? getVideoCallService;
  final void Function(VideoCallService?) setVideoCallService;
  final void Function(String callerName, Map<String, dynamic> offerData)
  onShowVideoCallDialog;
  const CallTab({
    super.key,
    required this.myUsername,
    required this.callService,
    required this.pipOverlay,
    required this.setVideoCallService,
    this.onIncomingCallReady,
    this.getVideoCallService,
    required this.onShowVideoCallDialog,
  });
  @override
  State<CallTab> createState() => _CallTabState();
}

class _CallTabState extends State<CallTab> {
  final _searchController = TextEditingController();
  CallService get _callService => widget.callService;

  bool _connected = false;
  bool _navigatingToCall = false;
  VideoCallService? get _videoCallService => widget.getVideoCallService?.call();

  String? _statusMessage;

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _setupCallbacks();
    if (_callService.isConnected) {
      _connected = true;
    } else {
      _callService.connect().then((_) {
        if (!mounted) return;
        setState(() => _connected = true);
      });
    }

    if (_callService.state == CallState.ringing &&
        _callService.remoteUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showIncomingCallDialog(_callService.remoteUser!);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingVideoCall();
    });
    _searchController.addListener(_onSearchChanged);
    _fetchListeners();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkPendingVideoCall() async {
    final caller = await AppStorage.getPendingVideoCaller();
    final sdp = await AppStorage.getPendingVideoSdp();

    if (caller == null || sdp == null) return;

    final expired = await AppStorage.isPendingVideoCallExpired();
    if (expired) {
      await AppStorage.clearPendingVideoCallData();
      return;
    }

    try {
      final res = await http.get(
        Uri.parse(
          "${AppConfig.httpBase}/call/video/pending/${widget.myUsername}",
        ),
      );
      if (res.statusCode != 200) {
        await AppStorage.clearPendingVideoCallData();
        return;
      }
      final data = jsonDecode(res.body);
      if (data["pending"] != true) {
        await AppStorage.clearPendingVideoCallData();
        return;
      }
    } catch (_) {
      await AppStorage.clearPendingVideoCallData();
      return;
    }

    await AppStorage.clearPendingVideoCallData();
    await FCMService.cancelVideoCallNotification();
    if (!mounted) return;

    final offerData = {'type': 'video_offer', 'sdp': sdp};
    _showIncomingVideoCallDialog(caller, offerData);
  }

  void _showIncomingVideoCallDialog(
    String callerName,
    Map<String, dynamic> offerData,
  ) {
    widget.onShowVideoCallDialog(callerName, offerData);
  }

  Future<void> _fetchListeners() async {
    try {
      setState(() {
        _allUsers = [];
        _filteredUsers = [];
      });
    } catch (_) {}
  }

  void _setupCallbacks() {
    _callService.onError = (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error), backgroundColor: _accent));
    };

    _callService.onIncomingCall = (callerName) {
      if (!mounted) return;

      if (widget.onIncomingCallReady != null) {
        widget.onIncomingCallReady!(callerName);
      } else {
        _showIncomingCallDialog(callerName);
      }
    };

    _callService.onCallStateChanged = (state) {
      debugPrint('CallTab: state=$state mounted=$mounted');
      if (!mounted) return;

      switch (state) {
        case CallState.calling:
          setState(() {
            _statusMessage = "Calling ${_callService.remoteUser}...";
          });
          break;

        case CallState.connected:
          setState(() {
            _statusMessage = null;
          });

          if (!_navigatingToCall) {
            _goToCallScreen();
          }
          break;

        case CallState.idle:
        case CallState.ended:
          debugPrint('CallTab idle/ended: _connected=$_connected');
          setState(() {
            _statusMessage = null;
            _connected = true;
          });
          _navigatingToCall = false;
          break;

        default:
          break;
      }
    };
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredUsers = List.from(_allUsers);
      } else {
        _filteredUsers = _allUsers.where((user) {
          return (user["username"] as String).toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _startCall(String username) async {
    await _callService.call(username);
  }

  void _goToCallScreen() {
    if (_navigatingToCall) {
      return;
    }

    if (_callService.remoteUser == null) {
      return;
    }

    _navigatingToCall = true;

    final remoteUser = _callService.remoteUser!;
    final startTime = DateTime.now();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ActiveCallScreen(callService: _callService, remoteUser: remoteUser),
      ),
    ).then((_) async {
      final duration = DateTime.now().difference(startTime).inSeconds;

      await CallLogStore.instance.add(
        CallLog(
          name: remoteUser,
          outgoing: _callService.state != CallState.ringing,
          missed: false,
          time: startTime,
          durationSeconds: duration,
        ),
      );

      _navigatingToCall = false;
    });
  }

  void _showIncomingCallDialog(String callerName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return IncomingCallDialog(
          callerName: callerName,
          callService: _callService,
          onAccept: () {
            Navigator.of(dialogContext).pop();
            _callService.acceptCall();
          },
          onReject: () async {
            Navigator.of(dialogContext).pop();
            _callService.rejectCall();
            await CallLogStore.instance.add(
              CallLog(
                name: callerName,
                outgoing: false,
                missed: true,
                time: DateTime.now(),
                durationSeconds: 0,
              ),
            );
          },
        );
      },
    ).then((_) {});

    _callService.onCallStateChanged = (state) {
      if (!mounted) return;
      if (state == CallState.connected) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _goToCallScreen();
      }
      if (state == CallState.ended) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _setupCallbacks();
      }
      if (state == CallState.idle) {
        setState(() => _connected = true);
        _navigatingToCall = false;
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'LAILA ',
                style: TextStyle(
                  color: _accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              TextSpan(
                text: 'NOW',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        actions: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 40),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _connected ? _green : _accent,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _statusMessage!,
                style: const TextStyle(color: _accent),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: _textPrimary),
                decoration: const InputDecoration(
                  hintText: "Search users...",
                  hintStyle: TextStyle(color: _textSecondary),
                  prefixIcon: Icon(Icons.search_rounded, color: _textSecondary),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _filteredUsers.isEmpty
                ? const Center(
                    child: Text(
                      "No users found",
                      style: TextStyle(color: _textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];

                      return UserTile(
                        username: user["username"],
                        online: user["online"] ?? false,
                        enabled:
                            _connected && _callService.state == CallState.idle,
                        onChat: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                myUsername: widget.myUsername,
                                otherUsername: user["username"],
                                callService: _callService,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
