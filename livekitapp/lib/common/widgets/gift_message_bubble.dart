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
        errorBuilder: (_, __, ___) => Icon(
          giftMessageIconFor(icon),
          color: const Color(0xFFE53950),
          size: size,
        ),
      ),
    );
  }
  return Icon(giftMessageIconFor(icon), color: const Color(0xFFE53950), size: size);
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

  const GiftMessageBubble({
    super.key,
    required this.giftIcon,
    required this.giftName,
    required this.coins,
    required this.isMe,
    this.sentDuringCall = false,
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
            Text(
              isMe ? 'You sent a gift' : 'Gift received',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              giftName,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on, color: Colors.amber, size: 14),
                const SizedBox(width: 3),
                Text(
                  '$coins coins',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (sentDuringCall) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.call, color: Colors.white38, size: 11),
                  SizedBox(width: 3),
                  Text(
                    'Sent during call',
                    style: TextStyle(
                      color: Colors.white38,
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
