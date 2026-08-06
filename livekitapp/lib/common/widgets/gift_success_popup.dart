import 'dart:math';
import 'package:flutter/material.dart';
import 'package:livekitapp/user/widgets/gift_sheet.dart';

/// Gravity-style downward acceleration applied to confetti pieces over the
/// animation. Larger values make pieces fall/curve down faster.
/// Kept top-level (rather than a class field) so both the painter and the
/// piece generator below can share a single source of truth.
const double kConfettiGravity = 90;

class _ConfettiPiece {
  final double startX;
  final double startY;
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double spin;
  final double delay;

  _ConfettiPiece({
    required this.startX,
    required this.startY,
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.spin,
    required this.delay,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double progress;

  _ConfettiPainter({required this.pieces, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final localT = ((progress - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (localT <= 0) continue;
      final distance = piece.speed * localT * size.height;
      final dx = piece.startX * size.width + cos(piece.angle) * distance;
      final dy = piece.startY * size.height +
          sin(piece.angle) * distance +
          kConfettiGravity * localT * localT;
      final opacity = (1 - localT).clamp(0.0, 1.0);
      final paint = Paint()..color = piece.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(piece.spin * localT * 2 * pi);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: piece.size, height: piece.size * 0.5),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ConfettiOverlay extends StatefulWidget {
  const _ConfettiOverlay();

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiPiece> _pieces;

  // ---------------------------------------------------------------------
  // Confetti customization — tweak these to change how the burst looks.
  // ---------------------------------------------------------------------

  /// Total number of confetti pieces in the burst.
  static const int kParticleCount = 90;

  /// How long the whole burst animation runs for.
  static const Duration kAnimationDuration = Duration(milliseconds: 1400);

  /// Where the burst originates from, as a fraction of the overlay size.
  /// (0.5, 0.5) is dead-center — right where the gift card sits — so the
  /// confetti explodes outward from it like a firecracker.
  static const double kOriginX = 0.5;
  static const double kOriginY = 0.5;

  /// The angle (in radians) the burst is centered on, measured from the
  /// positive x-axis, clockwise. Combined with kSpreadAngle below to cover
  /// the full circle for a firecracker-style radial explosion.
  static const double kBurstCenterAngle = 0;

  /// How wide the random spread is around the center angle above (radians).
  /// 2*pi (360°) sends pieces out in every direction from the origin.
  static const double kSpreadAngle = 2 * pi;

  /// Initial launch speed range, as a fraction of the overlay height/frame.
  static const double kMinSpeed = 0.55;
  static const double kMaxSpeed = 1.1;

  /// Gravity-style downward acceleration applied over the animation.
  /// See the top-level `kConfettiGravity` constant above — shared with the
  /// painter so there's a single place to change it.

  /// Piece size range (width in px; height is drawn at 0.5x width).
  static const double kMinPieceSize = 6;
  static const double kMaxPieceSize = 12;

  /// Spin speed range (full rotations over the piece's lifetime).
  static const double kMinSpin = 2;
  static const double kMaxSpin = 6;

  /// Small random stagger so not every piece launches at the exact same
  /// instant (fraction of the total animation duration).
  static const double kMaxStartDelay = 0.15;

  static const _colors = [
    Color(0xFFE53950),
    Color(0xFFFFC94A),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFFA855F7),
    Color(0xFFFF7AB6),
  ];

  @override
  void initState() {
    super.initState();
    final rand = Random();
    _pieces = [
      // Radial firecracker burst: every piece launches from the card
      // center and flies outward in a random direction across the full
      // circle, then gravity gradually pulls the arc downward.
      for (var i = 0; i < kParticleCount; i++)
        _ConfettiPiece(
          startX: kOriginX,
          startY: kOriginY,
          angle: kBurstCenterAngle +
              (rand.nextDouble() - 0.5) * kSpreadAngle,
          speed: kMinSpeed + rand.nextDouble() * (kMaxSpeed - kMinSpeed),
          size: kMinPieceSize +
              rand.nextDouble() * (kMaxPieceSize - kMinPieceSize),
          color: _colors[rand.nextInt(_colors.length)],
          spin: kMinSpin + rand.nextDouble() * (kMaxSpin - kMinSpin),
          delay: rand.nextDouble() * kMaxStartDelay,
        ),
    ];
    _controller = AnimationController(
      vsync: this,
      duration: kAnimationDuration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(pieces: _pieces, progress: _controller.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class GiftSuccessPopup extends StatefulWidget {
  final String? giftIcon;
  final String giftName;
  final int coins;
  final String? recipientName;

  const GiftSuccessPopup({
    super.key,
    required this.giftIcon,
    required this.giftName,
    required this.coins,
    this.recipientName,
  });

  static Future<void> show(
    BuildContext context, {
    required String? giftIcon,
    required String giftName,
    required int coins,
    String? recipientName,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Gift sent',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => GiftSuccessPopup(
        giftIcon: giftIcon,
        giftName: giftName,
        coins: coins,
        recipientName: recipientName,
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return Transform.scale(
          scale: 0.7 + 0.3 * curved.value,
          child: Opacity(opacity: animation.value, child: child),
        );
      },
    );
  }

  @override
  State<GiftSuccessPopup> createState() => _GiftSuccessPopupState();
}

class _GiftSuccessPopupState extends State<GiftSuccessPopup> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 26),
            decoration: BoxDecoration(
              color: const Color(0xFF141821),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 90,
                  width: 90,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2430),
                    shape: BoxShape.circle,
                  ),
                  child: buildGiftIcon(widget.giftIcon, size: 52),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Gift Sent!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.recipientName != null
                      ? '${widget.giftName} sent to ${widget.recipientName}'
                      : widget.giftName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.coins} coins',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned.fill(child: _ConfettiOverlay()),
        ],
      ),
    );
  }
}
