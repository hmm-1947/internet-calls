import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double height;
  const AppLogo({super.key, this.height = 49});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      height: height,
      fit: BoxFit.contain,
    );
  }
}
