import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:listener/services/video_call_services.dart';
import 'package:listener/screens/calls/video_call_screen.dart';
import 'package:listener/widgets/video_pip_overlay.dart';

class IncomingVideoCallDialog extends StatelessWidget {
  final String callerName;
  final Map<String, dynamic> offerData;
  final VideoCallService videoCallService;
  final VoidCallback onReject;
  final VideoPipOverlay pipOverlay;

  const IncomingVideoCallDialog({
    super.key,
    required this.callerName,
    required this.offerData,
    required this.videoCallService,
    required this.onReject,
    required this.pipOverlay,
  });

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
              callerName,
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
                    onPressed: onReject,
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
                    onPressed: () => _navigateAndAccept(context),
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

  void _navigateAndAccept(BuildContext context) async {
  final navigator = Navigator.of(context);

  final renderer = await pipOverlay.createRenderer();

  videoCallService.onRemoteStream = (stream) {
    renderer.srcObject = stream;
  };
  if (videoCallService.remoteStream != null) {
    renderer.srcObject = videoCallService.remoteStream;
  }

  navigator.pop();

  void doMinimize() {
  navigator.pop();
  pipOverlay.show(
    context: navigator.context,
    videoCallService: videoCallService,
    remoteUser: callerName,
    onMinimizeFromMaximized: doMinimize,
  );
}

  navigator.push(
    MaterialPageRoute(
      builder: (_) => VideoCallScreen(
        videoCallService: videoCallService,
        remoteUser: callerName,
        offerData: offerData,
        sharedRemoteRenderer: renderer,
        onMinimize: doMinimize,
      ),
    ),
  ).then((_) {
    if (!pipOverlay.isShowing) {
      pipOverlay.disposeRenderer();
    }
  });
}
}