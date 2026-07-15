import 'dart:async';
import 'package:flutter/material.dart';

class VoiceRecordingIndicator extends StatefulWidget {
  final Duration elapsed;
  final double amplitude;

  const VoiceRecordingIndicator({
    super.key,
    required this.elapsed,
    required this.amplitude,
  });

  @override
  State<VoiceRecordingIndicator> createState() =>
      _VoiceRecordingIndicatorState();
}

class _VoiceRecordingIndicatorState extends State<VoiceRecordingIndicator> {
  bool _blinkOn = true;
  Timer? _blinkTimer;
  final List<double> _levels = [];
  static const int _maxBars = 40;

  @override
  void initState() {
    super.initState();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      setState(() => _blinkOn = !_blinkOn);
    });
  }

  @override
  void didUpdateWidget(covariant VoiceRecordingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.amplitude != oldWidget.amplitude) {
      _levels.add(widget.amplitude);
      if (_levels.length > _maxBars) _levels.removeAt(0);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedOpacity(
          opacity: _blinkOn ? 1.0 : 0.2,
          duration: const Duration(milliseconds: 300),
          child: const Icon(
            Icons.fiber_manual_record,
            color: Colors.red,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),
        Text(_fmt(widget.elapsed)),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 24,
            child: CustomPaint(
              painter: _SpectrumPainter(List.of(_levels)),
              size: const Size(double.infinity, 24),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> levels;
  _SpectrumPainter(this.levels);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const barCount = 40;
    final gap = size.width / barCount;
    for (var i = 0; i < barCount; i++) {
      final levelIndex = levels.length - barCount + i;
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
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      oldDelegate.levels != levels;
}
