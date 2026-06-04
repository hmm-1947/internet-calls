import 'package:flutter/material.dart';

class ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const ControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? const Color(0xFF2ECC71).withOpacity(0.15)
                  : const Color(0xFF1A1A1A),
              border: Border.all(
                color: active
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFF2A2A2A),
              ),
            ),
            child: Icon(
              icon,
              color: active
                  ? const Color(0xFF2ECC71)
                  : const Color(0xFF888888),
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: active
                  ? const Color(0xFF2ECC71)
                  : const Color(0xFF888888),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}