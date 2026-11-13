import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

IconData giftMessageIconFor(String? icon) {
  switch (icon) {
    case 'rose':
      return Icons.local_florist;
    case 'diamond':
      return Icons.diamond;
    case 'truffle':
      return Icons.icecream;
    default:
      return Icons.card_giftcard;
  }
}

Widget _giftMessageImage(String? icon, {double size = 40}) {
  if (icon != null && (icon.startsWith('/') || icon.startsWith('http'))) {
    final url = icon.startsWith('http') ? icon : '${ApiConstants.baseUrl}$icon';
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        cacheHeight: (size * 3).round(),
        errorBuilder: (_, __, ___) => Icon(
          giftMessageIconFor(icon),
          color: AppColors.brand,
          size: size,
        ),
      ),
    );
  }
  return Icon(
    giftMessageIconFor(icon),
    color: AppColors.brand,
    size: size,
  );
}

/// Renders a gift as a chat bubble, used both in a normal chat thread and
/// for gifts sent mid-call. [coins] should be the FULL gift cost when shown
/// to the sender (user side), and the HALVED credited amount when shown to
/// the receiver (listener side) — the caller decides which to pass in.
class GiftMessageBubble extends StatelessWidget {
  final String? giftIcon;
  final String giftName;
  final int coins;
  final bool isMe;
  final bool sentDuringCall;

  /// How many identical, consecutive gifts this single bubble represents.
  /// 1 (the default) means "just this one gift" and no multiplier is shown.
  /// [coins] always stays the value of a single gift — it is never summed.
  final int stackCount;

  const GiftMessageBubble({
    super.key,
    required this.giftIcon,
    required this.giftName,
    required this.coins,
    required this.isMe,
    this.sentDuringCall = false,
    this.stackCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _giftMessageImage(giftIcon),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMe ? 'You sent a gift' : 'Gift received',
                  style: TextStyle(
                    color: context.c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (stackCount > 1) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'x$stackCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              giftName,
              style: TextStyle(color: context.c.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.monetization_on,
                  color: Colors.amber,
                  size: 14,
                ),
                const SizedBox(width: 3),
                Text(
                  '$coins coins',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (stackCount > 1)
                  Text(
                    '  •  sent $stackCount times',
                    style: TextStyle(
                      color: context.c.muted,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            if (sentDuringCall) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call, color: context.c.faint, size: 11),
                  SizedBox(width: 3),
                  Text(
                    'Sent during call',
                    style: TextStyle(
                      color: context.c.faint,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }
}
