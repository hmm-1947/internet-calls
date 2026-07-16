import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

class PulsingAvatarRing extends StatefulWidget {
  final double audioLevel;
  final bool showVideo;
  final VideoTrack? videoTrack;
  final String? photoUrl;
  const PulsingAvatarRing({
    super.key,
    required this.audioLevel,
    this.showVideo = false,
    this.videoTrack,
    this.photoUrl,
  });

  @override
  State<PulsingAvatarRing> createState() => _PulsingAvatarRingState();
}

class _PulsingAvatarRingState extends State<PulsingAvatarRing>
    with SingleTickerProviderStateMixin {
  static const int _barCount = 28;
  final List<double> _bars = List.filled(_barCount, 0.05);
  final _rand = Random();
  late final Ticker _ticker;
  double _displayLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

void _onTick(Duration elapsed) {
  final raw = widget.audioLevel.clamp(0.0, 1.0);

  if (raw > _displayLevel) {
    _displayLevel += (raw - _displayLevel) * 0.75;
  } else {
    _displayLevel += (raw - _displayLevel) * 0.18;
  }

  final t = elapsed.inMilliseconds / 1000.0;

  for (int i = 0; i < _barCount; i++) {
    final wave =
        sin(t * 10 + i * 0.55) * 0.35 +
        sin(t * 17 + i * 0.18) * 0.25;

    final random = (_rand.nextDouble() - 0.5) * 0.22;

    final modulation = (wave + random) * _displayLevel;

    _bars[i] = (_displayLevel + modulation)
        .clamp(0.04, 1.0);
  }

  if (mounted) {
    setState(() {});
  }
}


  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFE53950);
    final scale = 1.0 + pow(_displayLevel, 1.6) * 0.55;
    return SizedBox(
      width: 320,
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(320, 320),
            painter: _SpectrumPainter(bars: _bars, color: pink),
          ),
          Container(
            width: 260 * scale,
            height: 260 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: pink.withOpacity(0.35 + _displayLevel * 0.3),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
          ),
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: pink, width: 3),
            ),
            child: ClipOval(
              child: widget.showVideo && widget.videoTrack != null
                  ? VideoTrackRenderer(widget.videoTrack!)
                  : (ApiConstants.resolveMediaUrl(widget.photoUrl).isEmpty
                      ? Container(
                          color: const Color(0xFF2A2A2A),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white54,
                            size: 100,
                          ),
                        )
                      : Image.network(
                          ApiConstants.resolveMediaUrl(widget.photoUrl),
                          fit: BoxFit.cover,
                          width: 240,
                          height: 240,
                        )),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> bars;
  final Color color;
  _SpectrumPainter({required this.bars, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = 128.0;
    final barWidth = 4.0;
final maxBarHeight = 70.0;
    final paint = Paint()
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < bars.length; i++) {
      final angle = (2 * pi * i) / bars.length;
      final level = bars[i];
  final barHeight =
    3.0 + pow(level, 2.2) * maxBarHeight;
      final start = Offset(
        center.dx + baseRadius * cos(angle),
        center.dy + baseRadius * sin(angle),
      );
      final end = Offset(
        center.dx + (baseRadius + barHeight) * cos(angle),
        center.dy + (baseRadius + barHeight) * sin(angle),
      );
      paint.color = color.withOpacity(0.4 + level * 0.6);
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) => true;
}

class CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? background;
  final VoidCallback? onTap;
  const CallActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.background,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: background ?? const Color(0xFF1F2430),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class ConnectionQualityBars extends StatelessWidget {
  final ConnectionQuality quality;
  const ConnectionQualityBars({super.key, required this.quality});

  int _activeBars() {
    switch (quality) {
      case ConnectionQuality.excellent:
        return 4;
      case ConnectionQuality.good:
        return 3;
      case ConnectionQuality.poor:
        return 1;
      default:
        return 0;
    }
  }

  Color _color() {
    switch (quality) {
      case ConnectionQuality.excellent:
        return Colors.green;
      case ConnectionQuality.good:
        return Colors.amber;
      case ConnectionQuality.poor:
        return Colors.redAccent;
      default:
        return Colors.white24;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeBars();
    final color = _color();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final height = 4.0 + (i * 3);
        final isActive = i < active;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 4,
          height: height,
          decoration: BoxDecoration(
            color: isActive ? color : Colors.white24,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
