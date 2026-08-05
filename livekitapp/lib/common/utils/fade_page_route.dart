import 'dart:io';

import 'package:flutter/cupertino.dart';
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

Route<T> slideRoute<T>(Widget page) {
  if (Platform.isIOS) {
    return CupertinoPageRoute(builder: (_) => page);
  }

  return MaterialPageRoute(builder: (_) => page);
}
