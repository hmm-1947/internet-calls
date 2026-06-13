//active video calls
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitcalls/services/auth_service.dart';
import 'package:livekitcalls/services/coin_service.dart';
import '../../config/config.dart';
import '../../services/websocket_service.dart';

class ActiveVideoCallScreen extends StatefulWidget {
  final String room;
  final String token;
  final String listenerName;
  final WebSocketService wsService;

  const ActiveVideoCallScreen({
    super.key,
    required this.room,
    required this.token,
    required this.listenerName,
    required this.wsService,
  });

  @override
  State<ActiveVideoCallScreen> createState() => _ActiveVideoCallScreenState();
}

class _ActiveVideoCallScreenState extends State<ActiveVideoCallScreen> {
  Room? _room;
  bool _muted = false;
  bool _videoOff = false;
  bool _connecting = true;
  bool _waiting = true;
  final Stopwatch _callTimer = Stopwatch();
  Duration _duration = Duration.zero;
  Timer? _timer;
  late final StreamSubscription _wsSub;
  VideoTrack? _remoteVideoTrack;
  LocalVideoTrack? _localVideoTrack;

  @override
  void initState() {
    super.initState();
    _wsSub = widget.wsService.events.listen(_handleEvent);
    _joinCall();
  }

  Future<void> _handleEvent(Map<String, dynamic> message) async {
    final event = message['event'];
    if (event == 'call_accepted') {
  setState(() => _waiting = false);
  _callTimer.start();
  _timer = Timer.periodic(const Duration(seconds: 1), (_) {
    setState(() => _duration += const Duration(seconds: 1));
  });
} else if (event == 'call_rejected') {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Call was rejected')));
      }
    } else if (event == 'call_ended') {
  _timer?.cancel();
  _callTimer.stop();
  try {
    final token = await AuthService.getToken();
    await CoinService.deductCoins(token!, _callTimer.elapsed.inSeconds);
  } catch (_) {}
  if (mounted) Navigator.pop(context);
}
  }

  Future<void> _joinCall() async {
    try {
      final room = Room();
      room.addListener(_onRoomUpdate);
      await room.connect(AppConfig.livekitUrl, widget.token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      await room.localParticipant?.setCameraEnabled(true);
      final camTrack =
          room.localParticipant?.videoTrackPublications.firstOrNull?.track
              as LocalVideoTrack?;
      setState(() {
        _room = room;
        _localVideoTrack = camTrack;
        _connecting = false;
      });
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _onRoomUpdate() {
    for (final participant in _room!.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.track != null && pub.track is VideoTrack) {
          setState(() => _remoteVideoTrack = pub.track as VideoTrack);
          return;
        }
      }
    }
    setState(() => _remoteVideoTrack = null);
  }

  Future<void> _endCall() async {
  _timer?.cancel();
  _callTimer.stop();
  widget.wsService.send({'event': 'call_ended', 'to': widget.listenerName});
  await _room?.disconnect();
  try {
    final token = await AuthService.getToken();
    await CoinService.deductCoins(token!, _callTimer.elapsed.inSeconds);
  } catch (_) {}
  if (mounted) Navigator.pop(context);
}

  void _toggleMute() async {
    final newMuted = !_muted;
    await _room?.localParticipant?.setMicrophoneEnabled(!newMuted);
    setState(() => _muted = newMuted);
  }

  void _toggleVideo() async {
    final newVideoOff = !_videoOff;
    await _room?.localParticipant?.setCameraEnabled(!newVideoOff);
    setState(() => _videoOff = newVideoOff);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wsSub.cancel();
    _room?.removeListener(_onRoomUpdate);
    _room?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _connecting
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                _remoteVideoTrack != null
                    ? VideoTrackRenderer(_remoteVideoTrack!)
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.blue,
                              child: Icon(
                                Icons.headset,
                                size: 50,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.listenerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _waiting
                                  ? 'Calling...'
                                  : _formatDuration(_duration),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                if (_localVideoTrack != null && !_videoOff)
                  Positioned(
                    right: 16,
                    top: 48,
                    width: 100,
                    height: 150,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: VideoTrackRenderer(_localVideoTrack!),
                    ),
                  ),
                Positioned(
                  bottom: 48,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _VideoButton(
                        icon: _muted ? Icons.mic_off : Icons.mic,
                        label: _muted ? 'Unmute' : 'Mute',
                        color: _muted ? Colors.red : Colors.white24,
                        onTap: _toggleMute,
                      ),
                      GestureDetector(
                        onTap: _endCall,
                        child: const CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.red,
                          child: Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      _VideoButton(
                        icon: _videoOff ? Icons.videocam_off : Icons.videocam,
                        label: _videoOff ? 'Cam Off' : 'Cam On',
                        color: _videoOff ? Colors.red : Colors.white24,
                        onTap: _toggleVideo,
                      ),
                    ],
                  ),
                ),
                if (!_waiting)
                  Positioned(
                    top: 48,
                    left: 16,
                    child: Text(
                      _formatDuration(_duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _VideoButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _VideoButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}
