import 'package:flutter/material.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/coin_repository.dart';

IconData giftIconFor(String? icon) {
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

Widget buildGiftIcon(String? icon, {double size = 34}) {
  if (icon != null && (icon.startsWith('/') || icon.startsWith('http'))) {
    final url = icon.startsWith('http') ? icon : '${ApiConstants.baseUrl}$icon';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        cacheHeight: (size * 3).round(),
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (ctx, error, stack) => Icon(
          giftIconFor(icon),
          color: const Color(0xFFE53950),
          size: size,
        ),
      ),
    );
  }
  return Icon(
    giftIconFor(icon),
    color: const Color(0xFFE53950),
    size: size,
  );
}

Future<void> showGiftSheet(
  BuildContext context, {
  required int listenerId,
  int? callId,
  bool fromTop = false,
}) async {
  final localStorage = LocalStorage();
  final coinRepository = CoinRepository();
  int coins = 0;
  List<Map<String, dynamic>> gifts = [];
  try {
    final token = await localStorage.getToken();
    if (token != null) {
      coins = await coinRepository.getCoins(token);
      gifts = await coinRepository.getGiftCatalog(token);
    }
  } catch (_) {}
  if (!context.mounted) return;

  if (fromTop) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        pageBuilder: (ctx, anim, __) => GiftSheet(
          balance: coins,
          gifts: gifts,
          listenerId: listenerId,
          callId: callId,
          fromTop: true,
        ),
        transitionsBuilder: (ctx, animation, __, child) {
          final offset = Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
          return SlideTransition(position: offset, child: child);
        },
      ),
    );
    return;
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => GiftSheet(
      balance: coins,
      gifts: gifts,
      listenerId: listenerId,
      callId: callId,
      fromTop: false,
    ),
  );
}

class GiftSheet extends StatefulWidget {
  final int balance;
  final List<Map<String, dynamic>> gifts;
  final int listenerId;
  final int? callId;
  final bool fromTop;

  const GiftSheet({
    super.key,
    required this.balance,
    required this.gifts,
    required this.listenerId,
    this.callId,
    this.fromTop = false,
  });

  @override
  State<GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<GiftSheet> {
  late int _balance;
  final _localStorage = LocalStorage();
  final _coinRepository = CoinRepository();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
  }

  Future<void> _send(Map<String, dynamic> gift) async {
    final cost = gift['coins'] as int;
    if (_balance < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough coins')),
      );
      return;
    }
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final token = await _localStorage.getToken();
      final result = await _coinRepository.sendGift(
        token!,
        listenerId: widget.listenerId,
        giftId: gift['id'] as int,
        callId: widget.callId,
      );
      final sentCoins = result['gift_coins'] ?? cost;
      final giftName = result['gift_name'] ?? gift['name'];
      if (mounted) Navigator.of(context).pop();
      setState(() => _balance = result['coins'] ?? _balance);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sent $giftName for $sentCoins coins')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF141821),
        borderRadius: widget.fromTop
            ? const BorderRadius.vertical(bottom: Radius.circular(24))
            : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Send a Gift',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFFE53950)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 14,
            children: widget.gifts
                .map(
                  (g) => SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 40 - 20) / 3,
                    child: Column(
                      children: [
                          Container(
                            height: 80,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F2430),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: buildGiftIcon(g['icon'] as String?),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            g['name'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.monetization_on,
                                color: Colors.amber,
                                size: 14,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                g['coins'].toString(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE53950),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _sending ? null : () => _send(g),
                              child: const Text(
                                'SEND',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                    .toList(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Balance',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.monetization_on,
                        color: Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_balance Coins',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC94A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () {},
                child: const Text(
                  'Top up',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (widget.fromTop) {
      return SafeArea(
        child: Align(alignment: Alignment.topCenter, child: content),
      );
    }
    return content;
  }
}
