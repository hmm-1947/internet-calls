import 'package:flutter/material.dart';

Route<T> fadeRoute<T>(Widget page, {Color? barrierColor}) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    opaque: true,
    barrierColor: barrierColor,
  );
}
