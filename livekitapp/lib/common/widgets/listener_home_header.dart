import 'package:livekitapp/common/widgets/app_logo.dart';
import 'package:livekitapp/core/theme/app_theme.dart';
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
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: context.c.bg,
      alignment: Alignment.centerLeft,
      child: isHome
          ? const AppLogo()
          : Text(
              title,
              style: TextStyle(
                color: context.c.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}
