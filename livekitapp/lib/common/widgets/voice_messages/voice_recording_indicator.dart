import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class VoiceRecordingIndicator extends StatefulWidget {
  final ValueListenable<Duration> elapsed;
  final ValueListenable<double> amplitude;

  const VoiceRecordingIndicator({
    super.key,
    required this.elapsed,
    required this.amplitude,
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
  }

  @override
  void didUpdateWidget(covariant VoiceRecordingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.amplitude, widget.amplitude)) return;
    oldWidget.amplitude.removeListener(_onAmplitude);
    widget.amplitude.addListener(_onAmplitude);
  }

  void _onAmplitude() {
    _levels.add(widget.amplitude.value);
    if (_levels.length > _maxBars) _levels.removeAt(0);
    _revision.value++;
  }

  @override
  void dispose() {
    widget.amplitude.removeListener(_onAmplitude);
    _blink.dispose();
    _revision.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FadeTransition(
          opacity: _blink,
          child: const Icon(
            Icons.fiber_manual_record,
            color: Colors.red,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<Duration>(
          valueListenable: widget.elapsed,
          builder: (context, elapsed, _) => Text(
            _fmt(elapsed),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _SpectrumPainter(_levels, _revision),
              size: const Size(double.infinity, 24),
              child: const SizedBox(height: 24),
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
