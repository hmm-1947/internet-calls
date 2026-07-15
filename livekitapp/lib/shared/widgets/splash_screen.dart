import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: Center(
        child: Image.asset(
          'assets/images/splash.png',
          width: 180,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
