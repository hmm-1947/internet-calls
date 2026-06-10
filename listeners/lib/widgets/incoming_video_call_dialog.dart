import 'package:flutter/material.dart';
import 'package:listener/services/video_call_services.dart';
import 'package:listener/screens/calls/video_call_screen.dart';
import 'package:listener/widgets/video_pip_overlay.dart';

class IncomingVideoCallDialog extends StatefulWidget {
  final String callerName;
  final Map<String, dynamic> offerData;
  final VideoCallService videoCallService;
  final VoidCallback onReject;
  final VideoPipOverlay pipOverlay;
  final BuildContext shellContext;

  const IncomingVideoCallDialog({
    super.key,
    required this.callerName,
    required this.offerData,
    required this.videoCallService,
    required this.onReject,
    required this.pipOverlay,
    required this.shellContext,
  });

  @override
  State<IncomingVideoCallDialog> createState() =>
      _IncomingVideoCallDialogState();
}

class _IncomingVideoCallDialogState extends State<IncomingVideoCallDialog> {
  bool _dismissed = false;

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    final previousOnCallEnded = widget.videoCallService.onCallEnded;
    widget.videoCallService.onCallEnded = () {
      widget.pipOverlay.hide();
      widget.pipOverlay.disposeRenderer();
      _dismiss();
      previousOnCallEnded?.call();
      final shell = widget.shellContext;
      if (Navigator.of(shell).canPop()) {
        Navigator.of(shell).popUntil((route) => route.isFirst);
      }
    };
  }

  void _navigateAndAccept() async {
    final renderer = await widget.pipOverlay.createRenderer();

    if (!mounted) {
      widget.pipOverlay.disposeRenderer();
      return;
    }

    widget.videoCallService.onRemoteStream = (stream) {
      renderer.srcObject = stream;
    };
    if (widget.videoCallService.remoteStream != null) {
      renderer.srcObject = widget.videoCallService.remoteStream;
    }

    _dismiss();

    void doMinimize() {
      Navigator.of(widget.shellContext).pop();
      widget.pipOverlay.show(
        context: widget.shellContext,
        videoCallService: widget.videoCallService,
        remoteUser: widget.callerName,
        onMinimizeFromMaximized: doMinimize,
      );
    }

    Navigator.of(widget.shellContext)
        .push(
          MaterialPageRoute(
            builder: (_) => VideoCallScreen(
              videoCallService: widget.videoCallService,
              remoteUser: widget.callerName,
              offerData: widget.offerData,
              sharedRemoteRenderer: renderer,
              onMinimize: doMinimize,
            ),
          ),
        )
        .then((_) {
          if (!widget.pipOverlay.isShowing) {
            widget.pipOverlay.disposeRenderer();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF13131A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF3F51B5), Color(0xFF2ECC71)],
                ),
              ),
              child: const Icon(
                Icons.videocam_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'INCOMING VIDEO CALL',
              style: TextStyle(
                color: Color(0xFF8888AA),
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onReject,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A1010),
                      foregroundColor: const Color(0xFFFF3B6B),
                    ),
                    child: const Icon(Icons.call_end_rounded),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _navigateAndAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                    ),
                    child: const Icon(Icons.videocam_rounded),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
