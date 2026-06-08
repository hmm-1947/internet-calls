import 'dart:convert';
import 'package:calls/widgets/video_pip_overlay.dart';
import 'package:calls/core/config.dart';
import 'package:calls/screens/calls/video_call_screen.dart';
import 'package:calls/services/video_call_service.dart';
import 'package:calls/widgets/incoming_video_call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

  const CallTab({
    super.key,
    required this.myUsername,
    required this.callService,
    this.onIncomingCallReady,
  });

  @override
  State<CallTab> createState() => _CallTabState();
}

class _CallTabState extends State<CallTab> {
  final _searchController = TextEditingController();
  final _pipOverlay = VideoPipOverlay();
  late final CallService _callService;
  VideoCallService? _videoCallService;
  bool _connected = false;
  bool _navigatingToCall = false;

  String? _statusMessage;

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];

  @override
  void initState() {
    super.initState();

    _callService = widget.callService;

    _setupCallbacks();

    if (!_callService.isConnected) {
      _connect();
    } else {
      _connected = true;

      if (_callService.state == CallState.ringing &&
          _callService.remoteUser != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showIncomingCallDialog(_callService.remoteUser!);
        });
      }
    }

    _searchController.addListener(_onSearchChanged);
    _fetchListeners();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      await _callService.connect();

      if (!mounted) return;

      setState(() {
        _connected = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _statusMessage = "Connection failed";
      });
    }
  }

  Future<void> _fetchListeners() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_listeners');
      if (cached != null && _allUsers.isEmpty) {
        final list = jsonDecode(cached) as List;
        if (mounted) {
          setState(() {
            _allUsers = list
                .where((u) => u["username"] != widget.myUsername)
                .cast<Map<String, dynamic>>()
                .toList();
            _filteredUsers = List.from(_allUsers);
          });
        }
      }

      final response = await http.get(
        Uri.parse("${AppConfig.httpBase}/listeners"),
      );
      if (response.statusCode == 200) {
        await prefs.setString('cached_listeners', response.body);
        final listeners = jsonDecode(response.body) as List;
        if (mounted) {
          setState(() {
            _allUsers = listeners
                .where((u) => u["username"] != widget.myUsername)
                .cast<Map<String, dynamic>>()
                .toList();
            _filteredUsers = List.from(_allUsers);
          });
        }
      }
    } catch (_) {}
  }

  void _startVideoCall(String username) async {
    if (_videoCallService != null) return;

    _videoCallService = VideoCallService(callService: _callService);
    _callService.addVideoSignalListener(_onVideoSignal);

    final renderer = await _pipOverlay.createRenderer();

    _videoCallService!.onCallEnded = () {
      _pipOverlay.hide();
      _pipOverlay.disposeRenderer();
      _callService.removeVideoSignalListener(_onVideoSignal);
      _videoCallService?.dispose();
      _videoCallService = null;
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    };

    _videoCallService!.onRemoteStream = (stream) {
      renderer.srcObject = stream;
    };

    await _videoCallService!.call(username);
    if (!mounted) return;

    void doMinimize() {
      Navigator.of(context).pop();
      _pipOverlay.show(
        context: context,
        videoCallService: _videoCallService!,
        remoteUser: username,
        onMinimizeFromMaximized: doMinimize,
      );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          videoCallService: _videoCallService!,
          remoteUser: username,
          sharedRemoteRenderer: renderer,
          onMinimize: doMinimize,
        ),
      ),
    ).then((_) {
      if (!_pipOverlay.isShowing) {
        _pipOverlay.disposeRenderer();
        _callService.removeVideoSignalListener(_onVideoSignal);
        _videoCallService?.dispose();
        _videoCallService = null;
      }
    });
  }

  void _onVideoSignal(String type, Map<String, dynamic> data, String? from) {
    if (_videoCallService == null) return;
    switch (type) {
      case 'video_answer':
        _videoCallService!.handleAnswer(data);
        break;
      case 'video_candidate':
        _videoCallService!.handleCandidate(data);
        break;
      case 'video_hangup':
        _pipOverlay.hide();
        _pipOverlay.disposeRenderer();
        _videoCallService!.remoteHangup();
        _callService.removeVideoSignalListener(_onVideoSignal);
        _videoCallService?.dispose();
        _videoCallService = null;
        break;
    }
  }

  void _showIncomingVideoCallDialog(
    String callerName,
    Map<String, dynamic> offerData,
  ) {
    if (_videoCallService != null) return;

    _videoCallService = VideoCallService(callService: _callService);
    _callService.addVideoSignalListener(_onVideoSignal);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _videoCallService!.onCallEnded = () {
          _pipOverlay.hide();
          _pipOverlay.disposeRenderer();
          if (mounted) Navigator.of(dialogContext).pop();
          _callService.removeVideoSignalListener(_onVideoSignal);
          _videoCallService?.dispose();
          _videoCallService = null;
        };
        return IncomingVideoCallDialog(
          callerName: callerName,
          offerData: offerData,
          videoCallService: _videoCallService!,
          onReject: () {
            Navigator.of(dialogContext).pop();
            _callService.sendSignal(callerName, {'type': 'video_hangup'});
            _callService.clearPendingVideoOffer();
            _callService.removeVideoSignalListener(_onVideoSignal);
            _videoCallService?.dispose();
            _videoCallService = null;
          },
        );
      },
    );
  }

  void _setupCallbacks() {
    _callService.onError = (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error), backgroundColor: _accent));
    };

    _callService.onIncomingVideoCall = (callerName, offerData) {
      if (!mounted) return;
      _showIncomingVideoCallDialog(callerName, offerData);
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
          setState(() {
            _statusMessage = null;
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
    if (_navigatingToCall) return;
    if (_callService.remoteUser == null) return;

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
        widget.myUsername,
      );

      _navigatingToCall = false;
    });
  }

  void _showIncomingCallDialog(String callerName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return IncomingCallDialog(
          callerName: callerName,
          onAccept: () {
            Navigator.pop(context);
            _callService.acceptCall();
          },
          onReject: () async {
            Navigator.pop(context);

            _callService.rejectCall();

            await CallLogStore.instance.add(
              CallLog(
                name: callerName,
                outgoing: false,
                missed: true,
                time: DateTime.now(),
                durationSeconds: 0,
              ),
              widget.myUsername,
            );
          },
        );
      },
    );
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
                : RefreshIndicator(
                    color: _accent,
                    backgroundColor: _surface,
                    onRefresh: _fetchListeners,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];

                        return UserTile(
                          username: user["username"],
                          online: user["online"] ?? false,
                          enabled: _connected &&
                              _callService.state == CallState.idle,
                          onCall: () {
                            _startCall(user["username"]);
                          },
                          onVideoCall: () {
                            _startVideoCall(user["username"]);
                          },
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
          ),
        ],
      ),
    );
  }
}