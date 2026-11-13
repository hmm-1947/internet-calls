import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const double _logoSize = 180;
  static const double _ringSize = _logoSize + 48;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: _ringSize,
              height: _ringSize,
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.brand),
              ),
            ),
            Image.asset(
              'assets/images/app_logo.png',
              width: _logoSize,
              fit: BoxFit.contain,
            ),
          ],
        ),
      ),
    );
  }
}
