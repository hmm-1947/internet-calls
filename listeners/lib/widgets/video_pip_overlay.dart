import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:listener/screens/calls/video_call_screen.dart';
import 'package:listener/services/video_call_services.dart';


class VideoPipOverlay {
  OverlayEntry? _entry;
  bool _isShowing = false;
  RTCVideoRenderer? _sharedRemoteRenderer;

  bool get isShowing => _isShowing;
  RTCVideoRenderer? get sharedRemoteRenderer => _sharedRemoteRenderer;

  Future<RTCVideoRenderer> createRenderer() async {
    _sharedRemoteRenderer = RTCVideoRenderer();
    await _sharedRemoteRenderer!.initialize();
    return _sharedRemoteRenderer!;
  }

  void show({
    required BuildContext context,
    required VideoCallService videoCallService,
    required String remoteUser,
    required VoidCallback onMinimizeFromMaximized,
  }) {
    if (_isShowing) return;
    if (_sharedRemoteRenderer == null) return;
    _isShowing = true;

    _entry = OverlayEntry(
      builder: (_) => _PipBubble(
        remoteRenderer: _sharedRemoteRenderer!,
        remoteUser: remoteUser,
        onMaximize: () {
          hide();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VideoCallScreen(
                videoCallService: videoCallService,
                remoteUser: remoteUser,
                onMinimize: onMinimizeFromMaximized,
              ),
            ),
          );
        },
        onHangup: () {
          hide();
          disposeRenderer();
          videoCallService.hangup();
        },
      ),
    );

    Overlay.of(context).insert(_entry!);
  }

  void hide() {
    _entry?.remove();
    _entry = null;
    _isShowing = false;
  }

  void disposeRenderer() {
    _sharedRemoteRenderer?.dispose();
    _sharedRemoteRenderer = null;
  }
}

class _PipBubble extends StatefulWidget {
  final RTCVideoRenderer remoteRenderer;
  final String remoteUser;
  final VoidCallback onMaximize;
  final VoidCallback onHangup;

  const _PipBubble({
    required this.remoteRenderer,
    required this.remoteUser,
    required this.onMaximize,
    required this.onHangup,
  });

  @override
  State<_PipBubble> createState() => _PipBubbleState();
}

class _PipBubbleState extends State<_PipBubble> {
  double _x = 0;
  double _y = 0;
  bool _positioned = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    if (!_positioned) {
      _x = screenSize.width - 120;
      _y = screenSize.height - 220;
      _positioned = true;
    }

    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _x = (_x + details.delta.dx).clamp(0, screenSize.width - 110);
            _y = (_y + details.delta.dy).clamp(0, screenSize.height - 200);
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 110,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF3B6B), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 12,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  RTCVideoView(
                    widget.remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    left: 0,
                    right: 0,
                    child: Text(
                      widget.remoteUser,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: widget.onMaximize,
                          child: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.2),
                            ),
                            child: const Icon(
                              Icons.open_in_full_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: widget.onHangup,
                          child: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFE74C3C),
                            ),
                            child: const Icon(
                              Icons.call_end,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}