import 'package:flutter/material.dart';

class AutoHideNavBar extends StatelessWidget {
  final bool visible;
  final Widget child;

  const AutoHideNavBar({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0, 1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 260),
        opacity: visible ? 1 : 0,
        child: child,
      ),
    );
  }
}
