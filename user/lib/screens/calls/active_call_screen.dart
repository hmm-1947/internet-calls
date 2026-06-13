//active_call_screen
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitcalls/services/auth_service.dart';
import 'package:livekitcalls/services/coin_service.dart';
import 'package:livekitcalls/services/websocket_service.dart';
import '../../config/config.dart';

class ActiveCallScreen extends StatefulWidget {
  final String room;
  final String token;
  final String listenerName;
  final WebSocketService wsService;

  const ActiveCallScreen({
    super.key,
    required this.room,
    required this.token,
    required this.listenerName,
    required this.wsService,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  Room? _room;
  bool _muted = false;
  bool _speakerOn = true;
  bool _connecting = true;
  bool _waiting = true;
  final Stopwatch _callTimer = Stopwatch();
  Duration _duration = Duration.zero;
  Timer? _timer;
  late final StreamSubscription _wsSub;

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
      _startTimer();
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
      await room.connect(AppConfig.livekitUrl, widget.token);
      await room.localParticipant?.setMicrophoneEnabled(true);
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

  void _startTimer() {
  _callTimer.start();
  _timer = Timer.periodic(const Duration(seconds: 1), (_) {
    setState(() => _duration += const Duration(seconds: 1));
  });
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

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wsSub.cancel();
    _room?.disconnect();
    super.dispose();
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
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.headset, size: 50, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.listenerName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _waiting ? 'Calling...' : _formatDuration(_duration),
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
                        color: _speakerOn ? Colors.blue : Colors.white24,
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
