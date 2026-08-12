import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

/// True when the window is too small to lay out a normal call UI.
///
/// Android picture-in-picture shrinks the whole Flutter window to a thumbnail,
/// so the call controls, the screen underneath and the floating video window
/// all overflow at that size. This is deliberately driven by the measured size
/// rather than by the PiP callback alone: the platform notification and the
/// window resize do not arrive on the same frame, so the frames in between
/// would still be laid out with the wrong layout.
bool isCompactCallWindow(Size size) => size.width < 300 || size.height < 300;

class PulsingAvatarRing extends StatefulWidget {
  final ValueListenable<double> audioLevel;
  final bool showVideo;
  final VideoTrack? videoTrack;
  final String? photoUrl;
  final String? badgeLabel;
  final Color? badgeColor;
  const PulsingAvatarRing({
    super.key,
    required this.audioLevel,
    this.showVideo = false,
    this.videoTrack,
    this.photoUrl,
    this.badgeLabel,
    this.badgeColor,
  });

  @override
  State<PulsingAvatarRing> createState() => _PulsingAvatarRingState();
}

class _PulsingAvatarRingState extends State<PulsingAvatarRing>
    with SingleTickerProviderStateMixin {
  static const _referenceBoxSize = 320.0;
  static const _referencePhotoSize = 280.0;

  static const _epsilon = 0.004;

  static const _steps = 50;

  late final Ticker _ticker;
  final ValueNotifier<double> _glow = ValueNotifier<double>(0);
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.audioLevel.addListener(_onLevelChanged);
    _onLevelChanged();
  }

  @override
  void didUpdateWidget(PulsingAvatarRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.audioLevel, widget.audioLevel)) return;
    oldWidget.audioLevel.removeListener(_onLevelChanged);
    widget.audioLevel.addListener(_onLevelChanged);
    _onLevelChanged();
  }

  void _onLevelChanged() {
    if (_ticker.isActive) return;
    final target = widget.audioLevel.value.clamp(0.0, 1.0);
    if ((target - _level).abs() < _epsilon) return;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final target = widget.audioLevel.value.clamp(0.0, 1.0);
    final delta = target - _level;
    if (delta.abs() < _epsilon) {
      _level = target;
      _publish();
      _ticker.stop();
      return;
    }
    _level += delta * (delta > 0 ? 0.75 : 0.18);
    _publish();
  }

  void _publish() {
    final stepped = (_level * _steps).round() / _steps;
    if (_glow.value == stepped) return;
    _glow.value = stepped;
  }

  @override
  void dispose() {
    widget.audioLevel.removeListener(_onLevelChanged);
    _ticker.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _referenceBoxSize;
        final boxSize = math.min(_referenceBoxSize, availableWidth);
        final photoSize = _referencePhotoSize * (boxSize / _referenceBoxSize);

        return RepaintBoundary(
          child: SizedBox(
            width: boxSize,
            height: boxSize,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                _AvatarHalo(size: photoSize, level: _glow),
                _AvatarRingFace(
                  size: photoSize,
                  showVideo: widget.showVideo,
                  videoTrack: widget.videoTrack,
                  photoUrl: widget.photoUrl,
                ),
                if (!widget.showVideo &&
                    widget.badgeLabel != null &&
                    widget.badgeLabel!.isNotEmpty)
                  Positioned(
                    top: -(photoSize * 0.06),
                    child: _CallBadge(
                      label: widget.badgeLabel!,
                      color: widget.badgeColor ?? const Color(0xFFE11D48),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AvatarHalo extends StatelessWidget {
  final double size;
  final ValueListenable<double> level;

  const _AvatarHalo({required this.size, required this.level});

  static const _pink = Color(0xFFE53950);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: level,
        builder: (context, value, _) {
          final glowOpacity = 0.45 + value * 0.4;
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _pink.withValues(alpha: glowOpacity),
                  blurRadius: 30.0 + value * 50.0,
                  spreadRadius: 10.0 + value * 34.0,
                ),
                BoxShadow(
                  color: _pink.withValues(alpha: glowOpacity * 0.55),
                  blurRadius: 55.0 + value * 110.0,
                  spreadRadius: 22.0 + value * 70.0,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AvatarRingFace extends StatelessWidget {
  final double size;
  final bool showVideo;
  final VideoTrack? videoTrack;
  final String? photoUrl;

  const _AvatarRingFace({
    required this.size,
    required this.showVideo,
    required this.videoTrack,
    required this.photoUrl,
  });

  static const _pink = Color(0xFFE53950);

  @override
  Widget build(BuildContext context) {
    final track = videoTrack;
    final resolved = ApiConstants.resolveMediaUrl(photoUrl);
    final Widget face;
    if (showVideo && track != null) {
      face = VideoTrackRenderer(track);
    } else if (resolved.isEmpty) {
      face = Container(
        color: const Color(0xFF2A2A2A),
        child: const Icon(Icons.person, color: Colors.white54, size: 100),
      );
    } else {
      final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
      face = Image.network(
        resolved,
        fit: BoxFit.cover,
        width: size,
        height: size,
        cacheWidth: pixels,
        cacheHeight: pixels,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _pink.withValues(alpha: 0.9), width: 2.5),
      ),
      child: ClipOval(child: face),
    );
  }
}

class _CallBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CallBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, Colors.black, 0.25)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.6),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
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
