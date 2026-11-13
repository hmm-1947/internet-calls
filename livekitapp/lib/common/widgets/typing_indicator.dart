import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Animated "typing" label used in the chat app bar and the chat list.
///
/// The three dots ripple instead of sitting still, which reads as live activity
/// and makes a stale indicator obvious at a glance.
class TypingIndicator extends StatefulWidget {
  final Color color;
  final double fontSize;
  final String label;

  const TypingIndicator({
    super.key,
    this.color = AppColors.brand,
    this.fontSize = 12,
    this.label = 'typing',
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _dotPhase(double t, int index) {
    final shifted = (t - index * 0.18) % 1.0;
    if (shifted >= 0.6) return 0;
    final progress = shifted / 0.6;
    final triangle = progress < 0.5 ? progress * 2 : (1 - progress) * 2;
    return Curves.easeInOut.transform(triangle.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final dotSize = widget.fontSize * 0.34;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: widget.color,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 2),
                    child: _dot(dotSize, _dotPhase(_controller.value, i)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _dot(double size, double phase) {
    return Transform.translate(
      offset: Offset(0, -1.5 * phase),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.35 + 0.65 * phase),
        ),
      ),
    );
  }
}
