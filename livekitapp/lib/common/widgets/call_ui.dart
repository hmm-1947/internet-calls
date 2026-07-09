import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

class PulsingAvatarRing extends StatelessWidget {
  final double audioLevel;
  final bool showVideo;
  final VideoTrack? videoTrack;
  const PulsingAvatarRing({
    super.key,
    required this.audioLevel,
    this.showVideo = false,
    this.videoTrack,
  });

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFE53950);
    final scale = 1.0 + (audioLevel.clamp(0.0, 1.0) * 0.35);
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 220 * scale,
            height: 220 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: pink.withOpacity(
                    0.35 + audioLevel.clamp(0.0, 1.0) * 0.3,
                  ),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
          ),
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: pink, width: 3),
            ),
            child: ClipOval(
              child: showVideo && videoTrack != null
                  ? VideoTrackRenderer(videoTrack!)
                  : Container(
                      color: const Color(0xFF2A2A2A),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white54,
                        size: 90,
                      ),
                    ),
            ),
          ),
        ],
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
