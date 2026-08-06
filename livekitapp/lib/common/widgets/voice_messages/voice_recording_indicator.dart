import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class VoiceRecordingIndicator extends StatefulWidget {
  final ValueListenable<Duration> elapsed;
  final ValueListenable<double> amplitude;
  final ValueListenable<bool>? paused;
  final VoidCallback? onTogglePause;

  const VoiceRecordingIndicator({
    super.key,
    required this.elapsed,
    required this.amplitude,
    this.paused,
    this.onTogglePause,
  });

  @override
  State<VoiceRecordingIndicator> createState() =>
      _VoiceRecordingIndicatorState();
}

class _VoiceRecordingIndicatorState extends State<VoiceRecordingIndicator>
    with SingleTickerProviderStateMixin {
  static const int _maxBars = 40;

  final List<double> _levels = <double>[];
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    lowerBound: 0.2,
    upperBound: 1.0,
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    widget.amplitude.addListener(_onAmplitude);
    widget.paused?.addListener(_onPausedChanged);
  }

  @override
  void didUpdateWidget(covariant VoiceRecordingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.amplitude, widget.amplitude)) {
      oldWidget.amplitude.removeListener(_onAmplitude);
      widget.amplitude.addListener(_onAmplitude);
    }
    if (!identical(oldWidget.paused, widget.paused)) {
      oldWidget.paused?.removeListener(_onPausedChanged);
      widget.paused?.addListener(_onPausedChanged);
    }
  }

  void _onAmplitude() {
    if (widget.paused?.value == true) return;
    _levels.add(widget.amplitude.value);
    if (_levels.length > _maxBars) _levels.removeAt(0);
    _revision.value++;
  }

  void _onPausedChanged() {
    final paused = widget.paused?.value == true;
    if (paused) {
      _blink.stop();
      _blink.value = 1;
    } else if (!_blink.isAnimating) {
      _blink.repeat(reverse: true);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.amplitude.removeListener(_onAmplitude);
    widget.paused?.removeListener(_onPausedChanged);
    _blink.dispose();
    _revision.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _statusIcon(bool paused) {
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Icon(
        paused ? Icons.play_arrow_rounded : Icons.fiber_manual_record,
        key: ValueKey<bool>(paused),
        color: paused ? Colors.white : Colors.red,
        size: paused ? 20 : 16,
      ),
    );
    final content = paused ? icon : FadeTransition(opacity: _blink, child: icon);
    final toggle = widget.onTogglePause;
    if (toggle == null) {
      return SizedBox(width: 22, height: 22, child: Center(child: content));
    }
    return SizedBox(
      width: 26,
      height: 26,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: toggle, child: Center(child: content)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paused = widget.paused?.value == true;
    return Row(
      children: [
        _statusIcon(paused),
        const SizedBox(width: 8),
        ValueListenableBuilder<Duration>(
          valueListenable: widget.elapsed,
          builder: (context, elapsed, _) => Text(
            _fmt(elapsed),
            style: TextStyle(
              color: paused ? Colors.white54 : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: paused
              ? const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    'Paused',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: paused ? 0.35 : 1,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _SpectrumPainter(_levels, _revision),
                size: const Size(double.infinity, 24),
                child: const SizedBox(height: 24),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> levels;

  _SpectrumPainter(this.levels, Listenable repaint) : super(repaint: repaint);

  static const int _barCount = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final gap = size.width / _barCount;
    for (var i = 0; i < _barCount; i++) {
      final levelIndex = levels.length - _barCount + i;
      final amp = levelIndex >= 0 && levelIndex < levels.length
          ? levels[levelIndex]
          : 0.0;
      final h = (size.height * amp).clamp(2.0, size.height);
      final x = i * gap + gap / 2;
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) => false;
}
