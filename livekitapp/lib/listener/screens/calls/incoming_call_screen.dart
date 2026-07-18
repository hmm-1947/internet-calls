import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/screens/calls/listener_call_screen.dart';
import 'package:livekitapp/listener/services/ringtone_manager.dart';

class IncomingCallScreen extends StatefulWidget {
  final int callId;
  final String callerName;
  final String? callerPhotoUrl;
  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    this.callerPhotoUrl,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  bool _loading = false;
  AudioPlayer? _ringtonePlayer;

  @override
  void initState() {
    super.initState();
    _playRingtone();
  }

  Future<void> _playRingtone() async {
    try {
      _ringtonePlayer = AudioPlayer();
      final cachedPath = RingtoneManager.instance.currentRingtonePath;
      await _ringtonePlayer?.setLoopMode(LoopMode.one);
      if (cachedPath != null) {
        await _ringtonePlayer?.setFilePath(cachedPath);
      } else {
        await _ringtonePlayer?.setAsset('assets/audio/ringtone_default.mp3');
      }
      await _ringtonePlayer?.play();
    } catch (_) {}
  }

  Future<void> _stopRingtone() async {
    try {
      await _ringtonePlayer?.stop();
      await _ringtonePlayer?.dispose();
    } catch (_) {}
    _ringtonePlayer = null;
    try {
      await const MethodChannel('livekitapp/ringtone').invokeMethod('stopNativeRingtone');
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopRingtone();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _loading = true);
    _stopRingtone();
    try {
      final token = await _localStorage.getToken();
      final result = await _repository.acceptCall(token!, widget.callId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(_callRoute(result));
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Route _callRoute(Map<String, dynamic> result) {
    return PageRouteBuilder(
   pageBuilder: (_, __, ___) => ListenerCallScreen(
        url: result['livekit_url'],
        token: result['token'],
        callId: widget.callId,
        isVideo: result['call_type'] == 'video',
        otherPartyName: widget.callerName,
        otherPartyPhotoUrl: widget.callerPhotoUrl,
      ),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      opaque: true,
      barrierColor: Colors.black,
    );
  }

  Future<void> _reject() async {
    if (_loading) return;
    setState(() => _loading = true);
    _stopRingtone();
    try {
      final token = await _localStorage.getToken();
      await _repository.rejectCall(token!, widget.callId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
         AvatarImage(photoUrl: widget.callerPhotoUrl, radius: 48, iconSize: 48),
              const SizedBox(height: 16),
              Text(
                widget.callerName,
                style: const TextStyle(color: Colors.white, fontSize: 24),
              ),
              const SizedBox(height: 40),
              _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        FloatingActionButton(
                          heroTag: 'reject',
                          backgroundColor: Colors.red,
                          onPressed: _reject,
                          child: const Icon(Icons.call_end),
                        ),
                        FloatingActionButton(
                          heroTag: 'accept',
                          backgroundColor: Colors.green,
                          onPressed: _accept,
                          child: const Icon(Icons.call),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
