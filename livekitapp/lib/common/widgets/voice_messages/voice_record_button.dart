import 'package:livekitapp/core/theme/app_theme.dart';
import 'dart:async';
import 'dart:io';
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
  final void Function(bool paused)? onPauseChanged;
  final VoidCallback? onTooShort;
  final Color idleColor;
  const VoiceRecordButton({
    super.key,
    required this.onRecorded,
    this.onStateChanged,
    this.onLockChanged,
    this.onPauseChanged,
    this.onTooShort,
    this.idleColor = Colors.blue,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton>
    with TickerProviderStateMixin {
  final _recorder = AudioRecorder();
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _timer;
  bool _paused = false;
  bool _recording = false;
  bool _locked = false;
  bool _pressed = false;
  bool _lockBuzzed = false;
  bool _releasedEarly = false;
  bool _starting = false;
  double _dragDx = 0;
  double _dragDy = 0;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  double _amplitude = 0;
  String? _path;

  static const double _cancelThreshold = -90;
  static const double _lockThreshold = -70;
  static const _hintText = Color(0xFFB9C4D6);

  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  late final AnimationController _tapPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  void _pulseHint() {
    _buzz(10);
    _tapPulse.forward(from: 0);
  }

  double get _cancelProgress => (-_dragDx / -_cancelThreshold).clamp(0.0, 1.0);

  double get _lockProgress => (-_dragDy / -_lockThreshold).clamp(0.0, 1.0);

  void _buzz([int duration = 20]) {
    unawaited(
      Vibration.hasVibrator().then((hasVibrator) {
        if (hasVibrator) Vibration.vibrate(duration: duration);
      }),
    );
  }

  Future<void> _start() async {
    if (_starting || _recording) return;
    _starting = true;
    _releasedEarly = false;
    setState(() {
      _pressed = true;
      _dragDx = 0;
      _dragDy = 0;
      _locked = false;
      _lockBuzzed = false;
    });
    _showOverlay();
    _hint.repeat();
    _buzz(30);
    if (!await _recorder.hasPermission()) {
      _abortStart();
      return;
    }
    if (_releasedEarly || !mounted) {
      _abortStart();
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    if (_releasedEarly || !mounted) {
      try {
        await _recorder.stop();
      } catch (_) {}
      _discard(path);
      _abortStart();
      return;
    }
    _starting = false;
    setState(() {
      _recording = true;
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
      _path = path;
    });
    _halo.repeat(reverse: true);
    widget.onStateChanged?.call(true, Duration.zero, 0);
    _startTicker();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 150))
        .listen((amp) {
          if (!mounted) return;
          final normalized = ((amp.current + 45) / 45).clamp(0.0, 1.0);
          _amplitude = normalized;
          widget.onStateChanged?.call(true, _elapsed, _amplitude);
        });
  }

  void _abortStart() {
    _starting = false;
    _releasedEarly = false;
    _togglingPause = false;
    _path = null;
    _removeOverlay();
    _hint.stop();
    _halo.stop();
    if (mounted) {
      setState(() {
        _pressed = false;
        _recording = false;
        _locked = false;
        _paused = false;
        _dragDx = 0;
        _dragDy = 0;
      });
    }
    widget.onLockChanged?.call(false);
    widget.onPauseChanged?.call(false);
    widget.onStateChanged?.call(false, Duration.zero, 0);
  }

  void _handleRelease({required bool send}) {
    if (_locked) return;
    if (!_recording) {
      if (_pressed || _starting) _releasedEarly = true;
      return;
    }
    _stop(send: send);
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final startedAt = _startedAt;
      if (startedAt == null || _paused) return;
      _elapsed = DateTime.now().difference(startedAt);
      widget.onStateChanged?.call(true, _elapsed, _amplitude);
    });
  }

  Future<void> _stop({required bool send}) async {
    _starting = false;
    _releasedEarly = false;
    _togglingPause = false;
    _timer?.cancel();
    _timer = null;
    _ampSub?.cancel();
    _ampSub = null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    path ??= _path;
    _removeOverlay();
    _hint.stop();
    _halo.stop();
    final elapsed = _elapsed;
    final started = _startedAt;
    if (mounted) {
      setState(() {
        _recording = false;
        _pressed = false;
        _locked = false;
        _paused = false;
        _dragDx = 0;
        _dragDy = 0;
      });
    }
    _path = null;
    widget.onLockChanged?.call(false);
    widget.onPauseChanged?.call(false);
    widget.onStateChanged?.call(false, Duration.zero, 0);
    final keep =
        send && path != null && started != null && elapsed.inSeconds >= 1;
    if (!keep) {
      if (send && started != null && elapsed.inSeconds < 1) {
        widget.onTooShort?.call();
      }
      _discard(path);
      return;
    }
    widget.onRecorded(path, elapsed.inSeconds);
  }

  void _discard(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.delete();
    } catch (_) {}
  }

  void triggerCancel() => _cancelRecording();
  void triggerSend() => _stop(send: true);
  void triggerPause() => _togglePause();
  bool get isPaused => _paused;

  /// Guards against a second tap landing while the platform recorder is still
  /// switching state, which used to leave the button showing the wrong icon.
  bool _togglingPause = false;

  Future<void> _togglePause() async {
    if (!_recording || _togglingPause) return;
    _togglingPause = true;
    try {
      if (_paused) {
        try {
          await _recorder.resume();
        } catch (_) {
          return;
        }
        if (!mounted) return;
        _startedAt = DateTime.now().subtract(_elapsed);
        setState(() => _paused = false);
        _halo.repeat(reverse: true);
        _startTicker();
      } else {
        try {
          await _recorder.pause();
        } catch (_) {
          return;
        }
        _timer?.cancel();
        _timer = null;
        if (!mounted) return;
        setState(() => _paused = true);
        _halo.stop();
        widget.onStateChanged?.call(true, _elapsed, _amplitude);
      }
      widget.onPauseChanged?.call(_paused);
      _overlay?.markNeedsBuild();
    } finally {
      _togglingPause = false;
    }
  }

  void _cancelRecording() {
    _buzz(35);
    _stop(send: false);
  }

  void _lockRecording() {
    setState(() {
      _locked = true;
      _pressed = false;
      _dragDx = 0;
      _dragDy = 0;
    });
    _buzz(35);
    widget.onLockChanged?.call(true);
    _removeOverlay();
    _hint.stop();
  }

  void _showOverlay() {
    if (_overlay != null) return;
    _reveal.forward(from: 0);
    _overlay = OverlayEntry(
      builder: (context) {
        return CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(10, -4),
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: _reveal,
                builder: (context, child) {
                  final t = Curves.easeOutCubic.transform(_reveal.value);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - t)),
                      child: Transform.scale(
                        scale: 0.92 + 0.08 * t,
                        alignment: Alignment.bottomRight,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _buildOverlayContent(),
              ),
            ),
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
    final maxWidth = MediaQuery.sizeOf(context).width - 24;
    final width = maxWidth > 340 ? 340.0 : maxWidth;
    final lockProgress = _lockProgress;
    final cancelProgress = _cancelProgress;
    return SizedBox(
      width: width,
      height: 150,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 2,
            bottom: 30,
            child: Transform.translate(
              offset: Offset(0, -26 * lockProgress),
              child: Transform.scale(
                scale: 1 + 0.28 * lockProgress,
                child: _lockPill(lockProgress),
              ),
            ),
          ),
          Positioned(
            right: 58,
            bottom: 46,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: (1 - lockProgress * 1.6).clamp(0.0, 1.0),
              child: _hintLabel('Slide up to lock', Icons.keyboard_arrow_up),
            ),
          ),
          Positioned(
            right: 58,
            bottom: 6,
            child: Transform.translate(
              offset: Offset(_dragDx * 0.35, 0),
              child: Opacity(
                opacity: (1 - cancelProgress * 0.5).clamp(0.3, 1.0),
                child: _cancelHint(cancelProgress),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lockPill(double progress) {
    final ready = progress >= 0.99;
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Color.lerp(const Color(0xFF1F2740), widget.idleColor, progress),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.lock : Icons.lock_outline,
            color: context.c.text,
            size: 20,
          ),
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _hint,
            builder: (context, _) {
              final t = _hint.value;
              return Transform.translate(
                offset: Offset(0, -4 * t),
                child: Opacity(
                  opacity: (1 - t).clamp(0.25, 1.0),
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    color: context.c.textSecondary,
                    size: 16,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _hintLabel(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _hintText),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: _hintText, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _cancelHint(double progress) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: 1 + 0.5 * progress,
            child: Icon(
              Icons.delete_outline,
              size: 16,
              color: Color.lerp(_hintText, Colors.redAccent, progress),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedBuilder(
            animation: _hint,
            builder: (context, _) {
              final t = _hint.value;
              return Transform.translate(
                offset: Offset(-5 * t, 0),
                child: Opacity(
                  opacity: (1 - t).clamp(0.25, 1.0),
                  child: const Icon(
                    Icons.keyboard_arrow_left,
                    size: 16,
                    color: _hintText,
                  ),
                ),
              );
            },
          ),
          Text(
            progress >= 0.99 ? 'Release to cancel' : 'Slide to cancel',
            style: TextStyle(
              color: Color.lerp(_hintText, Colors.redAccent, progress),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (VoiceRecordButton.currentState == this) {
      VoiceRecordButton.currentState = null;
    }
    _timer?.cancel();
    _ampSub?.cancel();
    _removeOverlay();
    final pending = _path;
    _path = null;
    _hint.dispose();
    _halo.dispose();
    _reveal.dispose();
    _tapPulse.dispose();
    if (_recording && pending != null) {
      unawaited(
        Future<void>(() async {
          try {
            await _recorder.stop();
          } catch (_) {}
          _discard(pending);
          await _recorder.dispose();
        }),
      );
    } else {
      _recorder.dispose();
    }
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
            _lockRecording();
            return;
          }
          if (!_lockBuzzed && _lockProgress > 0.6) {
            _lockBuzzed = true;
            _buzz(12);
          } else if (_lockBuzzed && _lockProgress < 0.4) {
            _lockBuzzed = false;
          }
        },
        onLongPressEnd: (_) =>
            _handleRelease(send: _dragDx >= _cancelThreshold),
        onLongPressCancel: () => _handleRelease(send: false),
        // A plain tap is the most common mistake: nothing is recorded, so say
        // what the gesture actually is instead of failing silently.
        onTap: () {
          if (_recording || _starting) return;
          _pulseHint();
          widget.onTooShort?.call();
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: _locked ? 220 : 60),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(
            _locked ? 0 : _dragDx,
            _locked ? 0 : _dragDy.clamp(-70, 0),
            0,
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutBack,
            scale: _pressed ? 1.35 : 1.0,
            child: AnimatedBuilder(
              animation: _tapPulse,
              builder: (context, child) {
                final t = _tapPulse.value;
                final bump = 1 - (2 * t - 1).abs();
                return Transform.scale(
                  scale: 1 + 0.16 * Curves.easeOut.transform(bump),
                  child: child,
                );
              },
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (_recording && !_paused)
                      AnimatedBuilder(
                        animation: _halo,
                        builder: (context, _) => Container(
                          width: 44 + 18 * _halo.value,
                          height: 44 + 18 * _halo.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withValues(
                              alpha: 0.28 * (1 - _halo.value),
                            ),
                          ),
                        ),
                      ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _recording
                            ? (_paused ? const Color(0xFF8E2430) : Colors.red)
                            : widget.idleColor,
                      ),
                      alignment: Alignment.center,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: animation,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                        child: Icon(
                          _locked
                              ? Icons.lock
                              : (_recording ? Icons.mic : Icons.mic_none),
                          key: ValueKey<String>(
                            _locked
                                ? 'locked'
                                : (_recording ? 'recording' : 'idle'),
                          ),
                          color: context.c.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
