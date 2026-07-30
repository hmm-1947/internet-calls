import 'package:flutter/material.dart';

class ListenerHomeHeader extends StatelessWidget {
  final String title;
  final bool isHome;
  const ListenerHomeHeader({
    super.key,
    required this.title,
    this.isHome = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Color(0xFF0B0F1A),
      alignment: Alignment.centerLeft,
      child: isHome
          ? Image.asset(
              'assets/images/banner.png',
              height: 32,
              fit: BoxFit.contain,
            )
          : Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}
