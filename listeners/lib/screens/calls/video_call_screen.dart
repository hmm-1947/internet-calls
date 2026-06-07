import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:listener/services/video_call_services.dart';

class VideoCallScreen extends StatefulWidget {
  final VideoCallService videoCallService;
  final String remoteUser;
  final MediaStream? initialRemoteStream;
  final Map<String, dynamic>? offerData;

  const VideoCallScreen({
    super.key,
    required this.videoCallService,
    required this.remoteUser,
    this.initialRemoteStream,
    this.offerData,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _muted = false;
  bool _cameraOff = false;

  @override
  void initState() {
    super.initState();

    widget.videoCallService.onCallEnded = () {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    };

    widget.videoCallService.onRemoteStream = (stream) {
      if (mounted) {
        setState(() => _remoteRenderer.srcObject = stream);
      }
    };

    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    if (widget.offerData != null) {
      await widget.videoCallService.acceptCall(
        widget.offerData!,
        widget.remoteUser,
      );
    }

    _localRenderer.srcObject = widget.videoCallService.localStream;

    final remote =
        widget.initialRemoteStream ?? widget.videoCallService.remoteStream;
    if (remote != null) {
      _remoteRenderer.srcObject = remote;
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    widget.videoCallService.setMute(_muted);
  }

  void _toggleCamera() {
    setState(() => _cameraOff = !_cameraOff);
    widget.videoCallService.setCameraOff(_cameraOff);
  }

  void _hangup() {
    widget.videoCallService.hangup();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          Positioned(
            top: 48,
            right: 16,
            width: 100,
            height: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RTCVideoView(
                _localRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),
          Positioned(
            top: 52,
            left: 16,
            child: Text(
              widget.remoteUser,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ControlBtn(
                  icon: _muted ? Icons.mic_off : Icons.mic,
                  onTap: _toggleMute,
                  active: _muted,
                ),
                GestureDetector(
                  onTap: _hangup,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE74C3C),
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                _ControlBtn(
                  icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                  onTap: _toggleCamera,
                  active: _cameraOff,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  const _ControlBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? const Color(0xFFFF3B6B) : Colors.white24,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}