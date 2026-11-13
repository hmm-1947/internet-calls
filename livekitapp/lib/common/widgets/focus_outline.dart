import 'package:flutter/material.dart';
import 'package:livekitapp/core/theme/app_theme.dart';

class FocusOutline extends StatefulWidget {
  final Widget child;
  final double radius;
  final Color? fillColor;
  final Color? restColor;
  final EdgeInsets padding;
  final BoxConstraints? constraints;
  final double? width;
  final double borderWidth;

  const FocusOutline({
    super.key,
    required this.child,
    this.radius = 12,
    this.fillColor,
    this.restColor,
    this.padding = EdgeInsets.zero,
    this.constraints,
    this.width,
    this.borderWidth = 1.5,
  });

  @override
  State<FocusOutline> createState() => _FocusOutlineState();
}

class _FocusOutlineState extends State<FocusOutline> {
  bool _focused = false;

  double _deflate(double v) => (v - widget.borderWidth).clamp(0.0, double.infinity);

  @override
  Widget build(BuildContext context) {
    final p = widget.padding;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        if (mounted && f != _focused) setState(() => _focused = f);
      },
      child: Container(
        width: widget.width,
        constraints: widget.constraints,
        padding: EdgeInsets.fromLTRB(
          _deflate(p.left),
          _deflate(p.top),
          _deflate(p.right),
          _deflate(p.bottom),
        ),
        decoration: BoxDecoration(
          color: widget.fillColor ?? context.c.card,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: _focused
                ? AppColors.brand
                : (widget.restColor ?? Colors.transparent),
            width: widget.borderWidth,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
