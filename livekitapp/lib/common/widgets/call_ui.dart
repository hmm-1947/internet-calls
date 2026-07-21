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
  late final Ticker _ticker;
  double _displayLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final raw = widget.audioLevel.clamp(0.0, 1.0);

    // Glow grows quickly when someone starts speaking and eases back down
    // smoothly when they stop, so it "spreads and shrinks" with intensity.
    if (raw > _displayLevel) {
      _displayLevel += (raw - _displayLevel) * 0.75;
    } else {
      _displayLevel += (raw - _displayLevel) * 0.18;
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
    // Reference sizes for a normal-width screen; both scale down together
    // on narrow devices so the ring never overflows its parent.
    const referenceBoxSize = 320.0;
    const referencePhotoSize = 280.0;
    final level = _displayLevel.clamp(0.0, 1.0);

    // Halo strength scales with voice intensity: louder = bigger, brighter,
    // softer glow radiating out from behind the photo; quiet = it shrinks
    // back down to a subtle resting glow.
    final innerSpread = 10.0 + level * 34.0;
    final innerBlur = 30.0 + level * 50.0;
    final outerSpread = 22.0 + level * 70.0;
    final outerBlur = 55.0 + level * 110.0;
    final glowOpacity = 0.45 + level * 0.4;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : referenceBoxSize;
        final boxSize = referenceBoxSize < availableWidth
            ? referenceBoxSize
            : availableWidth;
        final photoSize = referencePhotoSize * (boxSize / referenceBoxSize);

        return SizedBox(
      width: boxSize,
      height: boxSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft radiant halo that spreads and shrinks with voice intensity.
          Container(
            width: photoSize,
            height: photoSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: pink.withOpacity(glowOpacity),
                  blurRadius: innerBlur,
                  spreadRadius: innerSpread,
                ),
                BoxShadow(
                  color: pink.withOpacity(glowOpacity * 0.55),
                  blurRadius: outerBlur,
                  spreadRadius: outerSpread,
                ),
              ],
            ),
          ),
          Container(
            width: photoSize,
            height: photoSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: pink.withOpacity(0.9),
                width: 2.5,
              ),
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
                          width: photoSize,
                          height: photoSize,
                        )),
            ),
          ),
        ],
      ),
        );
      },
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
