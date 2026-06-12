import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../config/config.dart';
import '../../services/websocket_service.dart';

class ActiveCallScreen extends StatefulWidget {
  final String room;
  final String token;
  final String callerName;
  final WebSocketService wsService;

  const ActiveCallScreen({
    super.key,
    required this.room,
    required this.token,
    required this.callerName,
    required this.wsService,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  Room? _room;
  bool _muted = false;
  bool _speakerOn = true;
  Duration _duration = Duration.zero;
  Timer? _timer;
  late final StreamSubscription _wsSub;
  bool _connecting = true;

  @override
  void initState() {
    super.initState();
    _joinCall();
    _wsSub = widget.wsService.events.listen(_handleEvent);
  }

  Future<void> _joinCall() async {
    try {
      final room = Room();
      await room.connect(AppConfig.livekitUrl, widget.token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      widget.wsService.send({
        'event': 'call_accepted',
        'to': widget.callerName,
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _duration += const Duration(seconds: 1));
      });
      setState(() {
        _room = room;
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

  Future<void> _endCall() async {
    _timer?.cancel();
    widget.wsService.send({'event': 'call_ended', 'to': widget.callerName});
    await _room?.disconnect();
    if (mounted) Navigator.pop(context);
  }

  void _toggleMute() async {
    final enabled = _room?.localParticipant?.isMicrophoneEnabled() ?? false;
    await _room?.localParticipant?.setMicrophoneEnabled(!enabled);
    setState(() => _muted = !enabled ? false : true);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _handleEvent(Map<String, dynamic> message) {
    if (message['event'] == 'call_ended') {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _room?.disconnect();
    super.dispose();
    _wsSub.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: _connecting
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const SizedBox(height: 60),
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.green,
                    child: Icon(Icons.person, size: 50, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.callerName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallButton(
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
                      _CallButton(
                        icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                        label: _speakerOn ? 'Speaker' : 'Earpiece',
                        color: _speakerOn ? Colors.green : Colors.white24,
                        onTap: () => setState(() => _speakerOn = !_speakerOn),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),
                ],
              ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallButton({
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
