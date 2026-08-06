import 'package:flutter/material.dart';

class HomeHeader extends StatelessWidget {
  final int? coins;
  final String title;
  final bool isHome;
  final Key? originKey;
  final Key? coinKey;
  const HomeHeader({
    super.key,
    required this.coins,
    required this.title,
    this.isHome = false,
    this.originKey,
    this.coinKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF0B0F1A),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          KeyedSubtree(
            key: originKey,
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
          ),
          Container(
            key: coinKey,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
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
                    style: const TextStyle(
                      color: Colors.white,
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
