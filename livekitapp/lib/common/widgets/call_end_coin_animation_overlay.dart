import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/call_end_coin_animation.dart';

enum _Face { walk, point, drink, satisfied }

class CallEndCoinAnimationOverlay extends StatefulWidget {
  final GlobalKey originKey;
  final GlobalKey coinKey;

  const CallEndCoinAnimationOverlay({
    super.key,
    required this.originKey,
    required this.coinKey,
  });

  @override
  State<CallEndCoinAnimationOverlay> createState() =>
      _CallEndCoinAnimationOverlayState();
}

class _CallEndCoinAnimationOverlayState
    extends State<CallEndCoinAnimationOverlay>
    with SingleTickerProviderStateMixin {
  static const _skin = Color(0xFFF3C29B);
  static const _hair = Color(0xFF10141F);
  static const _hoodie = Color(0xFFE11D48);
  static const _hoodieDark = Color(0xFFB01238);
  static const _accent = Color(0xFFE53950);
  static const _blush = Color(0xFFFF8FA3);
  static const _straw = Color(0xFFFFE082);

  late AnimationController _controller;
  Offset? _p0;
  Offset? _p1;
  Offset? _p2;
  Offset? _target;
  int _coinCount = 4;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    );
    callEndCoinAnimationNotifier.addListener(_onRequest);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _active = false);
      }
    });
  }

  void _onRequest() {
    final request = callEndCoinAnimationNotifier.value;
    if (request == null) return;
    _coinCount = request.coins.clamp(1, 8);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    final overlayBox = context.findRenderObject() as RenderBox?;
    final originBox =
        widget.originKey.currentContext?.findRenderObject() as RenderBox?;
    final coinBox =
        widget.coinKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || originBox == null || coinBox == null) return;
    if (!overlayBox.attached || !originBox.attached || !coinBox.attached) {
      return;
    }

    final originGlobal = originBox.localToGlobal(
      Offset(originBox.size.width / 2, originBox.size.height),
    );
    final coinGlobal = coinBox.localToGlobal(
      Offset(coinBox.size.width / 2, coinBox.size.height / 2),
    );
    final p0 = overlayBox.globalToLocal(originGlobal);
    final target = overlayBox.globalToLocal(coinGlobal);
    final p1 = Offset(p0.dx, p0.dy + 78);
    final p2 = Offset(
      (target.dx - 48).clamp(28.0, overlayBox.size.width - 28.0),
      p1.dy,
    );

    _controller.duration = Duration(
      milliseconds: 5000 + (_coinCount - 1) * 220,
    );

    setState(() {
      _p0 = p0;
      _p1 = p1;
      _p2 = p2;
      _target = target;
      _active = true;
    });
    _controller.forward(from: 0);
  }

  double _seg(double v, double start, double end) {
    if (end <= start) return v >= end ? 1 : 0;
    return ((v - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    callEndCoinAnimationNotifier.removeListener(_onRequest);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_active ||
        _p0 == null ||
        _p1 == null ||
        _p2 == null ||
        _target == null) {
      return const SizedBox.shrink();
    }
    final p0 = _p0!;
    final p1 = _p1!;
    final p2 = _p2!;
    final target = _target!;
    final angle = math.atan2(target.dy - p2.dy, target.dx - p2.dx);

    const bp1 = 0.12;
    const bp2 = 0.30;
    const bp3 = 0.44;
    const bp4 = 0.56;
    const bp5 = 0.60;
    const bp6 = 0.84;
    const bp7 = 0.90;
    const bp8 = 0.93;
    const bp9 = 0.97;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final v = _controller.value;

          final popIn = Curves.easeOutBack.transform(_seg(v, 0.0, bp1));
          final descend = Curves.easeInOutCubic.transform(_seg(v, bp1, bp2));
          final slide = Curves.easeInOutCubic.transform(_seg(v, bp2, bp3));
          final strawIn = Curves.easeOutBack.transform(_seg(v, bp3, bp4));
          final strawBack = Curves.easeInCubic.transform(_seg(v, bp7, bp8));
          final strawOut = (strawIn - strawBack).clamp(0.0, 1.0);
          final pointArm = Curves.easeOutCubic.transform(_seg(v, bp3, bp4));
          final walkBack1 = Curves.easeInOutCubic.transform(_seg(v, bp8, bp9));
          final walkBack2 = Curves.easeInOutCubic.transform(_seg(v, bp9, 1.0));
          final popBack = Curves.easeInBack.transform(_seg(v, 0.96, 1.0));

          Offset personPos;
          double facing = 1;
          if (v < bp1) {
            personPos = p0;
          } else if (v < bp2) {
            personPos = Offset.lerp(p0, p1, descend)!;
          } else if (v < bp3) {
            personPos = Offset.lerp(p1, p2, slide)!;
          } else if (v < bp8) {
            personPos = p2;
          } else if (v < bp9) {
            personPos = Offset.lerp(p2, p1, walkBack1)!;
            facing = -1;
          } else {
            personPos = Offset.lerp(p1, p0, walkBack2)!;
            facing = -1;
          }

          final walking = (v > bp1 && v < bp3) || v > bp8;
          final bob = walking ? math.sin(v * math.pi * 14) * 3 : 0.0;

          _Face face;
          double gulp = 0;
          double blush = 0;
          double sparkle = 0;
          if (v < bp3) {
            face = _Face.walk;
          } else if (v < bp5) {
            face = _Face.point;
          } else if (v < bp7) {
            face = _Face.drink;
            blush = Curves.easeOut.transform(_seg(v, bp5, bp5 + 0.05));
            final segWidth = (bp6 - bp5) / _coinCount;
            for (var i = 0; i < _coinCount; i++) {
              final s = bp5 + segWidth * i;
              final e = s + segWidth;
              final local = _seg(v, s + segWidth * 0.55, e);
              if (local > 0 && local < 1) {
                gulp = math.sin(local * math.pi);
              }
            }
          } else if (v < bp9) {
            face = _Face.satisfied;
            blush = 1;
            sparkle = 1 - Curves.easeIn.transform(_seg(v, bp7 + 0.03, bp8));
          } else {
            face = _Face.walk;
          }

          final entryScale = v < bp1 ? popIn : 1.0;
          final exitScale = v >= 0.96 ? (1.0 - popBack) : 1.0;
          final scale = (entryScale * exitScale).clamp(0.0, 1.2);
          final opacity = (v < bp1 ? popIn.clamp(0.0, 1.0) : 1.0) *
              (v >= 0.96 ? (1.0 - popBack).clamp(0.0, 1.0) : 1.0);

          final coins = List.generate(_coinCount, (i) {
            final segWidth = (bp6 - bp5) / _coinCount;
            final start = bp5 + segWidth * i;
            final end = start + segWidth * 0.9;
            final progress = Curves.easeIn.transform(_seg(v, start, end));
            if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
            final arc = Offset(
              target.dx + (p2.dx - target.dx) * progress,
              target.dy +
                  (p2.dy - target.dy) * progress -
                  math.sin(progress * math.pi) * 18,
            );
            final coinScale = 1.0 - progress * 0.6;
            return Positioned(
              left: arc.dx - 6,
              top: arc.dy - 6,
              child: Transform.scale(
                scale: coinScale.clamp(0.25, 1.0),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.amber.shade800, width: 1),
                  ),
                ),
              ),
            );
          });

          return Stack(
            children: [
              Positioned(
                left: personPos.dx - 65,
                top: personPos.dy - 108 + bob,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..scale(facing, 1.0),
                      child: _Character(
                        face: face,
                        strawOut: strawOut,
                        pointArm: pointArm,
                        armAngle: angle,
                        gulp: gulp,
                        blush: blush,
                        sparkle: sparkle,
                        skin: _skin,
                        hair: _hair,
                        hoodie: _hoodie,
                        hoodieDark: _hoodieDark,
                        accent: _accent,
                        blushColor: _blush,
                        strawColor: _straw,
                      ),
                    ),
                  ),
                ),
              ),
              ...coins,
            ],
          );
        },
      ),
    );
  }
}

class _Character extends StatelessWidget {
  final _Face face;
  final double strawOut;
  final double pointArm;
  final double armAngle;
  final double gulp;
  final double blush;
  final double sparkle;
  final Color skin;
  final Color hair;
  final Color hoodie;
  final Color hoodieDark;
  final Color accent;
  final Color blushColor;
  final Color strawColor;

  const _Character({
    required this.face,
    required this.strawOut,
    required this.pointArm,
    required this.armAngle,
    required this.gulp,
    required this.blush,
    required this.sparkle,
    required this.skin,
    required this.hair,
    required this.hoodie,
    required this.hoodieDark,
    required this.accent,
    required this.blushColor,
    required this.strawColor,
  });

  static const double _w = 130;
  static const double _h = 190;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _w,
      height: _h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: const Size(_w, _h),
            painter: _CharacterPainter(
              face: face,
              strawOut: strawOut,
              pointArm: pointArm,
              armAngle: armAngle,
              gulp: gulp,
              blush: blush,
              skin: skin,
              hair: hair,
              hoodie: hoodie,
              hoodieDark: hoodieDark,
              accent: accent,
              blushColor: blushColor,
              strawColor: strawColor,
            ),
          ),
          if (sparkle > 0)
            Positioned(
              right: 4,
              top: -8,
              child: Opacity(
                opacity: sparkle.clamp(0.0, 1.0),
                child: Icon(
                  Icons.star_rounded,
                  size: 20,
                  color: Colors.amber.shade300,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CharacterPainter extends CustomPainter {
  final _Face face;
  final double strawOut;
  final double pointArm;
  final double armAngle;
  final double gulp;
  final double blush;
  final Color skin;
  final Color hair;
  final Color hoodie;
  final Color hoodieDark;
  final Color accent;
  final Color blushColor;
  final Color strawColor;

  _CharacterPainter({
    required this.face,
    required this.strawOut,
    required this.pointArm,
    required this.armAngle,
    required this.gulp,
    required this.blush,
    required this.skin,
    required this.hair,
    required this.hoodie,
    required this.hoodieDark,
    required this.accent,
    required this.blushColor,
    required this.strawColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final headCenter = Offset(cx - 3, 38);
    const headRadius = 29.0;
    final shoulderL = Offset(cx - 27, 76);
    final shoulderR = Offset(cx + 27, 76);
    final hipL = Offset(cx - 17, 148);
    final hipR = Offset(cx + 17, 148);
    final mouthPos = Offset(headCenter.dx + 5, headCenter.dy + 16);

    _paintLegs(canvas, hipL, hipR);
    _paintTorso(canvas, shoulderL, shoulderR, hipL, hipR);
    _paintFarArm(canvas, shoulderL);
    _paintStrawArm(canvas, shoulderR, mouthPos);
    _paintHead(canvas, headCenter, headRadius, mouthPos);
  }

  void _paintLegs(Canvas canvas, Offset hipL, Offset hipR) {
    final legPaint = Paint()..color = const Color(0xFF3A3F4B);
    final shoePaint = Paint()..color = const Color(0xFF23262E);
    final shoeAccent = Paint()..color = accent;
    for (final hip in [hipL, hipR]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(hip.dx - 9, hip.dy, 18, 38),
          const Radius.circular(8),
        ),
        legPaint,
      );
      final shoeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(hip.dx - 12, hip.dy + 34, 27, 12),
        const Radius.circular(6),
      );
      canvas.drawRRect(shoeRect, shoePaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(hip.dx - 12, hip.dy + 34, 27, 4),
          const Radius.circular(3),
        ),
        shoeAccent,
      );
    }
  }

  void _paintTorso(Canvas canvas, Offset sL, Offset sR, Offset hL, Offset hR) {
    // blazer body
    final bodyPaint = Paint()..color = hoodie;
    final path = Path()
      ..moveTo(sL.dx, sL.dy)
      ..quadraticBezierTo(sL.dx - 9, (sL.dy + hL.dy) / 2, hL.dx - 6, hL.dy)
      ..lineTo(hR.dx + 6, hR.dy)
      ..quadraticBezierTo(sR.dx + 9, (sR.dy + hR.dy) / 2, sR.dx, sR.dy)
      ..quadraticBezierTo((sL.dx + sR.dx) / 2, sL.dy - 16, sL.dx, sL.dy)
      ..close();
    canvas.drawPath(path, bodyPaint);
    canvas.drawPath(
      path,
      Paint()
        ..color = hoodieDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // shirt collar wedge under the lapels
    final collarPaint = Paint()..color = const Color(0xFFF4F6FA);
    final collarPath = Path()
      ..moveTo((sL.dx + sR.dx) / 2, sL.dy - 12)
      ..lineTo((sL.dx + sR.dx) / 2 - 12, sL.dy + 20)
      ..lineTo((sL.dx + sR.dx) / 2, sL.dy + 6)
      ..lineTo((sL.dx + sR.dx) / 2 + 12, sL.dy + 20)
      ..close();
    canvas.drawPath(collarPath, collarPaint);

    // tie
    final tiePaint = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH((sL.dx + sR.dx) / 2 - 3.6, sL.dy - 2, 7.2, 30),
        const Radius.circular(3),
      ),
      tiePaint,
    );

    // lapels
    final lapelPaint = Paint()..color = hoodieDark;
    final lapelL = Path()
      ..moveTo((sL.dx + sR.dx) / 2, sL.dy - 10)
      ..lineTo(sL.dx + 6, sL.dy + 4)
      ..lineTo((sL.dx + sR.dx) / 2 - 6, sL.dy + 26)
      ..close();
    final lapelR = Path()
      ..moveTo((sL.dx + sR.dx) / 2, sL.dy - 10)
      ..lineTo(sR.dx - 6, sR.dy + 4)
      ..lineTo((sL.dx + sR.dx) / 2 + 6, sR.dy + 26)
      ..close();
    canvas.drawPath(lapelL, lapelPaint);
    canvas.drawPath(lapelR, lapelPaint);

    // button
    canvas.drawCircle(
      Offset((sL.dx + sR.dx) / 2, hL.dy - 22),
      2.6,
      Paint()..color = hoodieDark,
    );
  }

  void _paintFarArm(Canvas canvas, Offset shoulder) {
    final sleeve = Paint()
      ..color = hoodie
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;
    final cuff = Paint()..color = skin;
    final swing = pointArm > 0 ? -0.55 * pointArm : 0.06;
    final elbow = shoulder + Offset(math.sin(swing) * 10, 33);
    final hand = elbow + const Offset(2, 23);
    canvas.drawPath(
      Path()
        ..moveTo(shoulder.dx, shoulder.dy)
        ..lineTo(elbow.dx, elbow.dy)
        ..lineTo(hand.dx, hand.dy),
      sleeve,
    );
    canvas.drawCircle(hand, 7.6, cuff);
  }

  void _paintStrawArm(Canvas canvas, Offset shoulder, Offset mouthPos) {
    final t = strawOut.clamp(0.0, 1.0);
    // straw reaches from the mouth out toward the coin counter (armAngle
    // points from the character to the counter), instead of a pocket.
    const reach = 130.0;
    final dir = Offset(math.cos(armAngle), math.sin(armAngle));
    final strawBase = mouthPos + const Offset(1, 1);
    final tip = strawBase + dir * (reach * t);

    final sleeve = Paint()
      ..color = hoodie
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;

    if (t > 0.02) {
      final elbow = Offset.lerp(shoulder, tip, 0.45)! + const Offset(6, 10);
      canvas.drawPath(
        Path()
          ..moveTo(shoulder.dx, shoulder.dy)
          ..quadraticBezierTo(elbow.dx, elbow.dy, tip.dx - dir.dx * 10, tip.dy - dir.dy * 10),
        sleeve,
      );
      canvas.drawLine(
        strawBase,
        tip,
        Paint()
          ..color = strawColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset.lerp(strawBase, tip, 0.35)!,
        Offset.lerp(strawBase, tip, 0.48)!,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      // gripping hand partway along the straw, near the mouth end
      final gripPoint = Offset.lerp(strawBase, tip, 0.22)!;
      canvas.drawCircle(gripPoint, 7.8, Paint()..color = skin);
    } else {
      final elbow = shoulder + const Offset(-3, 33);
      final hand = elbow + const Offset(-2, 21);
      canvas.drawPath(
        Path()
          ..moveTo(shoulder.dx, shoulder.dy)
          ..lineTo(elbow.dx, elbow.dy)
          ..lineTo(hand.dx, hand.dy),
        sleeve,
      );
      canvas.drawCircle(hand, 7.6, Paint()..color = skin);
    }
  }


  void _paintHead(Canvas canvas, Offset center, double radius, Offset mouthPos) {
    // ears
    final earPaint = Paint()..color = skin;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx - radius + 2, center.dy + 3), width: 9, height: 14),
      earPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx + radius - 2, center.dy + 3), width: 9, height: 14),
      earPaint,
    );

    // back hair mass
    final hairPaint = Paint()..color = hair;
    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(0, 3),
        width: radius * 2 + 10,
        height: radius * 2 + 16,
      ),
      hairPaint,
    );

    // neck
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(center.dx - 8, center.dy + radius - 6, 16, 16),
        const Radius.circular(6),
      ),
      Paint()..color = skin,
    );

    // face
    canvas.drawOval(
      Rect.fromCenter(center: center, width: radius * 1.92, height: radius * 2.1),
      Paint()..color = skin,
    );

    // side-part layered fringe
    final fringe = Path()
      ..moveTo(center.dx - radius - 3, center.dy - 6)
      ..quadraticBezierTo(
        center.dx - radius - 2,
        center.dy - radius - 6,
        center.dx - radius * 0.25,
        center.dy - radius - 12,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.05,
        center.dy - radius - 4,
        center.dx + radius * 0.1,
        center.dy - radius - 13,
      )
      ..quadraticBezierTo(
        center.dx + radius * 0.55,
        center.dy - radius - 15,
        center.dx + radius + 2,
        center.dy - radius + 2,
      )
      ..quadraticBezierTo(
        center.dx + radius + 4,
        center.dy - 4,
        center.dx + radius - 2,
        center.dy + 6,
      )
      ..quadraticBezierTo(
        center.dx + radius * 0.5,
        center.dy - radius + 6,
        center.dx + radius * 0.1,
        center.dy - radius * 0.55,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.2,
        center.dy - radius + 4,
        center.dx - radius * 0.5,
        center.dy - radius * 0.4,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.75,
        center.dy - radius + 12,
        center.dx - radius + 3,
        center.dy + 4,
      )
      ..close();
    canvas.drawPath(fringe, hairPaint);

    if (blush > 0) {
      final blushPaint = Paint()
        ..color = blushColor.withValues(alpha: 0.55 * blush.clamp(0.0, 1.0));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx - radius * 0.56, center.dy + 8),
          width: 13,
          height: 8,
        ),
        blushPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx + radius * 0.56, center.dy + 8),
          width: 13,
          height: 8,
        ),
        blushPaint,
      );
    }

    _paintEye(canvas, Offset(center.dx - radius * 0.42, center.dy - 1));
    _paintEye(canvas, Offset(center.dx + radius * 0.42, center.dy - 1));

    final browPaint = Paint()
      ..color = hair
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final browY = center.dy - radius * 0.42;
    canvas.drawLine(
      Offset(center.dx - radius * 0.62, browY),
      Offset(center.dx - radius * 0.18, browY - 2.4),
      browPaint,
    );
    canvas.drawLine(
      Offset(center.dx + radius * 0.18, browY - 2.4),
      Offset(center.dx + radius * 0.62, browY),
      browPaint,
    );

    // shaded nose
    canvas.drawPath(
      Path()
        ..moveTo(center.dx + 1.5, center.dy - 2)
        ..quadraticBezierTo(center.dx + 5, center.dy + 6, center.dx + 1, center.dy + 9)
        ..quadraticBezierTo(center.dx - 2, center.dy + 9.5, center.dx - 0.5, center.dy + 8),
      Paint()
        ..color = const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx + 1, center.dy + 9), width: 5, height: 2.6),
      Paint()..color = const Color(0x1F000000),
    );

    _paintMouth(canvas, Offset(mouthPos.dx - 3, mouthPos.dy - 5));
  }

  void _paintEye(Canvas canvas, Offset pos) {
    if (face == _Face.drink || face == _Face.satisfied) {
      canvas.drawPath(
        Path()
          ..moveTo(pos.dx - 7, pos.dy)
          ..quadraticBezierTo(pos.dx, pos.dy - 7, pos.dx + 7, pos.dy),
        Paint()
          ..color = hair
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    final scleraRect = Rect.fromCenter(center: pos, width: 15, height: 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(scleraRect, const Radius.circular(7)),
      Paint()..color = Colors.white,
    );
    canvas.drawOval(
      Rect.fromCenter(center: pos + const Offset(0, 1.5), width: 10, height: 11),
      Paint()..color = hair,
    );
    canvas.drawOval(
      Rect.fromCenter(center: pos + const Offset(0, 1.5), width: 5, height: 5.6),
      Paint()..color = hair.withValues(alpha: 0.55),
    );
    canvas.drawCircle(pos + const Offset(-2.4, -1.6), 2.2, Paint()..color = Colors.white);
    canvas.drawArc(
      scleraRect.inflate(1.0),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = hair
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  void _paintMouth(Canvas canvas, Offset pos) {
    switch (face) {
      case _Face.point:
        canvas.drawOval(
          Rect.fromCenter(center: pos, width: 12, height: 10),
          Paint()..color = hoodieDark,
        );
        break;
      case _Face.drink:
        final g = 7 + gulp * 5;
        canvas.drawOval(
          Rect.fromCenter(center: pos, width: g, height: g),
          Paint()..color = hoodieDark,
        );
        break;
      case _Face.satisfied:
        canvas.drawPath(
          Path()
            ..moveTo(pos.dx - 12, pos.dy - 3)
            ..quadraticBezierTo(pos.dx, pos.dy + 9, pos.dx + 12, pos.dy - 3),
          Paint()
            ..color = hair
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2
            ..strokeCap = StrokeCap.round,
        );
        break;
      case _Face.walk:
        canvas.drawPath(
          Path()
            ..moveTo(pos.dx - 7, pos.dy - 1.5)
            ..quadraticBezierTo(pos.dx, pos.dy + 4, pos.dx + 7, pos.dy - 1.5),
          Paint()
            ..color = hair
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _CharacterPainter oldDelegate) {
    return oldDelegate.face != face ||
        oldDelegate.strawOut != strawOut ||
        oldDelegate.pointArm != pointArm ||
        oldDelegate.armAngle != armAngle ||
        oldDelegate.gulp != gulp ||
        oldDelegate.blush != blush;
  }
}
