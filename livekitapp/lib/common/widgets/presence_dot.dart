import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PresenceDot extends StatelessWidget {
  final ValueListenable<bool?> presence;
  final bool fallback;
  final Color borderColor;
  final double size;

  const PresenceDot({
    super.key,
    required this.presence,
    this.fallback = false,
    this.borderColor = const Color(0xFF0B0F1A),
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: presence,
      builder: (context, online, _) {
        if (!(online ?? fallback)) return const SizedBox.shrink();
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
          ),
        );
      },
    );
  }
}
