//listener active_call_screen
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:listener/core/config.dart';
import 'package:listener/core/storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../services/call_service.dart';
import '../../widgets/control_button.dart';

class ActiveCallScreen extends StatefulWidget {
  final CallService callService;
  final String remoteUser;

  const ActiveCallScreen({
    super.key,
    required this.callService,
    required this.remoteUser,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  Timer? _timer;
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;
  String? _myRole;
  int _seconds = 0;

  bool _muted = false;
  bool _speakerOn = false;

  void Function(CallState)? _previousStateCallback;

  @override
  void initState() {
    super.initState();

    Helper.setSpeakerphoneOn(true);
    _startTimer();
    _previousStateCallback = widget.callService.onCallStateChanged;

    widget.callService.onCallStateChanged = (state) {
      _previousStateCallback?.call(state);
      if ((state == CallState.ended || state == CallState.idle) && mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    };
  }

  @override
  void dispose() {
    _timer?.cancel();

    widget.callService.onCallStateChanged = _previousStateCallback;
    // _stopAndUploadRecording();
    _recorder.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      setState(() {
        _seconds++;
      });
    });
  }

  // Future<void> _stopAndUploadRecording() async {
  //   if (_myRole != 'listener' || _recordingPath == null) return;
  //   final path = await _recorder.stop();
  //   if (path == null) return;
  //   final file = File(path);
  //   if (!await file.exists()) return;
  //   final request = http.MultipartRequest(
  //     'POST',
  //     Uri.parse('${AppConfig.httpBase}/recordings/upload'),
  //   );
  //   request.fields['caller'] = widget.remoteUser;
  //   request.fields['listener'] = widget.callService.myUsername;
  //   request.files.add(await http.MultipartFile.fromPath('file', path));
  //   await request.send();
  // }

  // Future<void> _loadRoleAndRecord() async {
  //   _myRole = await AppStorage.getRole();
  //   if (_myRole == 'listener') {
  //     final dir = await getExternalStorageDirectory();
  //     _recordingPath =
  //         '${dir?.path}/rec_${widget.remoteUser}_${DateTime.now().millisecondsSinceEpoch}.aac';
  //     await _recorder.start(
  //       const RecordConfig(
  //         encoder: AudioEncoder.aacLc,
  //         sampleRate: 16000,
  //         numChannels: 1,
  //         noiseSuppress: false,
  //         echoCancel: false,
  //       ),
  //       path: _recordingPath!,
  //     );
  //   }
  // }

  String get _formattedTime {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');

    final seconds = (_seconds % 60).toString().padLeft(2, '0');

    return "$minutes:$seconds";
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
    });

    widget.callService.setMute(_muted);
  }

  void _hangup() {
    widget.callService.hangup();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A1A1A),
                border: Border.all(color: const Color(0xFF2ECC71), width: 2),
              ),
              child: Center(
                child: Text(
                  widget.remoteUser[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.remoteUser,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formattedTime,
              style: const TextStyle(
                color: Color(0xFF2ECC71),
                fontSize: 18,
                fontWeight: FontWeight.w500,
                letterSpacing: 2,
              ),
            ),
            const Spacer(flex: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ControlButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    label: _muted ? "Unmute" : "Mute",
                    active: _muted,
                    onTap: _toggleMute,
                  ),
                  GestureDetector(
                    onTap: _hangup,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFE74C3C),
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  ControlButton(
                    icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                    label: "Speaker",
                    active: _speakerOn,
                    onTap: () {
                      setState(() => _speakerOn = !_speakerOn);
                      Helper.setSpeakerphoneOn(_speakerOn);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
