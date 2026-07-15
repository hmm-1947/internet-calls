import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:vibration/vibration.dart';

class VoiceRecordButton extends StatefulWidget {
  static _VoiceRecordButtonState? currentState;
  final void Function(String filePath, int durationSeconds) onRecorded;

  final void Function(bool recording, Duration elapsed, double amplitude)?
  onStateChanged;

  final void Function(bool locked)? onLockChanged;
  final Color idleColor;
  const VoiceRecordButton({
    super.key,
    required this.onRecorded,
    this.onStateChanged,

    this.onLockChanged,
    this.idleColor = Colors.blue,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  final _recorder = AudioRecorder();
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _timer;
  bool _paused = false;
  bool _recording = false;
  bool _locked = false;
  bool _pressed = false;
  double _dragDx = 0;
  double _dragDy = 0;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  double _amplitude = 0;
  String? _path;

  static const double _cancelThreshold = -90;
  static const double _lockThreshold = -70;

  Future<void> _start() async {
    setState(() {
      _pressed = true;
      _dragDx = 0;
      _dragDy = 0;
      _locked = false;
    });
    _showOverlay();
    unawaited(
      Vibration.hasVibrator().then((v) {
        if (v ?? false) Vibration.vibrate(duration: 30);
      }),
    );
    if (!await _recorder.hasPermission()) {
      _removeOverlay();
      setState(() => _pressed = false);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    if (!mounted) return;
    setState(() {
      _recording = true;
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
      _path = path;
    });
    widget.onStateChanged?.call(true, Duration.zero, 0);
    widget.onStateChanged?.call(true, Duration.zero, 0);
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_startedAt == null || _paused) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt!));
      widget.onStateChanged?.call(true, _elapsed, _amplitude);
    });
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 150))
        .listen((amp) {
          final normalized = ((amp.current + 45) / 45).clamp(0.0, 1.0);
          setState(() => _amplitude = normalized);
          widget.onStateChanged?.call(true, _elapsed, _amplitude);
        });
  }

  Future<void> _stop({required bool send}) async {
    _timer?.cancel();
    _ampSub?.cancel();
    String? path;
    if (_paused) {
      path = _path;
    } else {
      path = await _recorder.stop();
    }
    _removeOverlay();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _pressed = false;
      _locked = false;
      _paused = false;
      _dragDx = 0;
      _dragDy = 0;
    });
    widget.onLockChanged?.call(false);
    widget.onStateChanged?.call(false, Duration.zero, 0);
    if (!send || path == null || _startedAt == null) return;
    final duration = _elapsed.inSeconds;
    if (duration < 1) return;
    widget.onRecorded(path, duration);
  }

  void triggerCancel() => _cancelRecording();
  void triggerSend() => _stop(send: true);
  void triggerPause() => _togglePause();
  bool get isPaused => _paused;
  Future<void> _togglePause() async {
    if (_paused) {
      await _recorder.resume();
      setState(() => _paused = false);
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_startedAt == null || _paused) return;
        setState(() => _elapsed += const Duration(milliseconds: 100));
        widget.onStateChanged?.call(true, _elapsed, _amplitude);
      });
    } else {
      await _recorder.pause();
      _timer?.cancel();
      setState(() => _paused = true);
      widget.onStateChanged?.call(true, _elapsed, _amplitude);
    }
    _overlay?.markNeedsBuild();
  }

  void _cancelRecording() {
    _stop(send: false);
  }

  void _showOverlay() {
    _overlay = OverlayEntry(
      builder: (context) {
        return CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -8),
          child: Material(
            color: Colors.transparent,
            child: _buildOverlayContent(),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Widget _buildOverlayContent() {
    final screenWidth = MediaQuery.of(context).size.width;
    return IgnorePointer(
      ignoring: !_locked,
      child: SizedBox(
        width: screenWidth,
        height: 160,
        child: Stack(
          alignment: Alignment.bottomRight,
          clipBehavior: Clip.none,
          children: [
            if (!_locked)
              Positioned(
                right: 28,
                bottom: 70,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  curve: Curves.easeOut,
                  transform: Matrix4.translationValues(
                    0,
                    _dragDy.clamp(-70, 0),
                    0,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                    child: const Icon(Icons.lock_outline, color: Colors.blue),
                  ),
                ),
              ),
            if (!_locked)
              Positioned(
                right: 60,
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chevron_left,
                      color: Colors.black45,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Slide to cancel',
                      style: TextStyle(
                        color: Colors.black.withOpacity(
                          (1.0 - (_dragDx.abs() / 90)).clamp(0.2, 0.6),
                        ),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _removeOverlay();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    VoiceRecordButton.currentState = this;
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onLongPressStart: (_) => _start(),
        onLongPressMoveUpdate: (details) {
          if (!_recording || _locked) return;
          setState(() {
            _dragDx = details.offsetFromOrigin.dx.clamp(-200, 0);
            _dragDy = details.offsetFromOrigin.dy.clamp(-200, 0);
          });
          _overlay?.markNeedsBuild();
          if (_dragDx < _cancelThreshold) {
            _cancelRecording();
            return;
          }
          if (_dragDy < _lockThreshold) {
            setState(() {
              _locked = true;
              _pressed = false;
            });
            widget.onLockChanged?.call(true);
            _overlay?.markNeedsBuild();
            Future.delayed(const Duration(milliseconds: 250), () {
              if (!mounted) return;
              setState(() {
                _dragDx = 0;
                _dragDy = 0;
              });
            });
          }
        },
        onLongPressEnd: (_) {
          if (_locked || !_recording) return;
          if (_dragDx < _cancelThreshold) {
            _stop(send: false);
          } else {
            _stop(send: true);
          }
        },
        onLongPressCancel: () {
          if (_locked) return;
          _stop(send: false);
        },
        onTap: () {
          if (_locked) return;
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: _locked ? 250 : 0),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(
            _dragDx,
            _locked ? -90 : _dragDy.clamp(-70, 0),
            0,
          ),
          child: Transform.scale(
            scale: _pressed ? 1.4 : 1.0,
            alignment: Alignment.center,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: _recording ? Colors.red : widget.idleColor,
              child: Icon(
                _recording ? Icons.mic : Icons.mic_none,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
