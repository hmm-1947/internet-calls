import 'package:livekitapp/common/widgets/app_logo.dart';
import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class HomeHeader extends StatelessWidget {
  final int? coins;
  final String title;
  final bool isHome;
  const HomeHeader({
    super.key,
    required this.coins,
    required this.title,
    this.isHome = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: context.c.bg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          isHome
              ? const AppLogo()
              : Text(
                  title,
                  style: TextStyle(
                    color: context.c.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: context.c.overlay,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.monetization_on,
                  color: Colors.amber,
                  size: 16,
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 34,
                  child: Text(
                    coins == null ? '' : '$coins',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
