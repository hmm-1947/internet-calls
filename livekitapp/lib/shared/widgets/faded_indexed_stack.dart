import 'package:flutter/material.dart';

class FadedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  State<FadedIndexedStack> createState() => _FadedIndexedStackState();
}

class _FadedIndexedStackState extends State<FadedIndexedStack> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: widget.index != i,
            child: AnimatedOpacity(
              opacity: widget.index == i ? 1 : 0,
              duration: widget.duration,
              child: widget.children[i],
            ),
          ),
      ],
    );
  }
}
