import 'package:livekitapp/core/theme/app_theme.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class CrownNavBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> icons;
  final List<String> labels;
  final VoidCallback onCrownTap;
  final bool showCrown;
  final IconData crownIcon;
  final String? crownImageAsset;
  final double crownSize;

  const CrownNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.icons,
    required this.labels,
    required this.onCrownTap,
    this.showCrown = true,
    this.crownIcon = Icons.emoji_events,
    this.crownImageAsset,
    this.crownSize = 60,
  });

  @override
  State<CrownNavBar> createState() => _CrownNavBarState();
}

class _CrownNavBarState extends State<CrownNavBar> {
  DateTime? _lastTapAt;
  static const _debounceDuration = Duration(milliseconds: 350);

  void _handleTap(int index) {
    final now = DateTime.now();
    if (_lastTapAt != null && now.difference(_lastTapAt!) < _debounceDuration) {
      return;
    }
    _lastTapAt = now;
    if (index != widget.selectedIndex) {
      HapticFeedback.selectionClick();
      widget.onDestinationSelected(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    const activeColor = AppColors.brand;
    final itemCount = widget.icons.length;

    Widget buildItem(int i) {
      final selected = widget.selectedIndex == i;
      final color = selected ? activeColor : context.c.textSecondary;
      return Expanded(
        child: InkWell(
          onTap: () => _handleTap(i),
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  key: ValueKey('nav_icon_$i\_$selected'),
                  tween: Tween<double>(begin: 1.0, end: selected ? 1.25 : 1.0),
                  duration: const Duration(milliseconds: 260),
                  curve: selected ? Curves.elasticOut : Curves.easeOut,
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: IconTheme(
                    data: IconThemeData(color: color, size: 22),
                    child: widget.icons[i],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final barHeight = 78 + bottomInset;
    // How far the crown button pokes above the bar. Anything drawn above the
    // bar's own box is not hit-testable by default, so this is handled by
    // _OverflowHitTestBox below.
    final overhang = widget.showCrown
        ? (widget.crownSize - 42).clamp(0.0, double.infinity)
        : 0.0;

    final content = SizedBox(
      height: barHeight + overhang,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: barHeight,
            child: Container(
              decoration: BoxDecoration(
                color: context.c.bg,
                border: Border(top: BorderSide(color: context.c.border)),
              ),
              child: ClipRect(
                child: ColoredBox(
                  color: Colors.transparent,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final slotCount = widget.showCrown
                              ? itemCount + 1
                              : itemCount;
                          final slotWidth = constraints.maxWidth / slotCount;
                          final crownSlot = itemCount ~/ 2;
                          final slotIndex =
                              widget.showCrown &&
                                  widget.selectedIndex >= crownSlot
                              ? widget.selectedIndex + 1
                              : widget.selectedIndex;
                          return Stack(
                            children: [
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 320),
                                curve: Curves.easeOutCubic,
                                left: slotIndex * slotWidth + 4,
                                top: 0,
                                width: slotWidth - 8,
                                height: 56,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: context.c.brandTint,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: AppColors.brand.withValues(alpha: 0.35),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  buildItem(0),
                                  buildItem(1),
                                  if (widget.showCrown)
                                    const Expanded(child: SizedBox()),
                                  for (var i = 2; i < itemCount; i++)
                                    buildItem(i),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.showCrown)
            Positioned(
              // Sits at the top of this (taller) box, which places it the same
              // distance above the bar as before: a 60px button pokes ~38px
              // above, so the offset scales off that reference.
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: widget.onCrownTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: widget.crownSize,
                    height: widget.crownSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.crownImageAsset == null
                          ? context.c.brandTint
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withOpacity(0.5),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: widget.crownImageAsset != null
                        ? ClipOval(
                            child: Image.asset(
                              widget.crownImageAsset!,
                              width: widget.crownSize,
                              height: widget.crownSize,
                              fit: BoxFit.cover,
                              cacheWidth:
                                  (widget.crownSize *
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ))
                                      .round(),
                            ),
                          )
                        : Icon(
                            widget.crownIcon,
                            color: AppColors.brandDark,
                            size: widget.crownSize * 28 / 60,
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (overhang == 0) return RepaintBoundary(child: content);

    // Reports only `barHeight` to the Scaffold (so the body's bottom padding is
    // unchanged) while painting and hit-testing the crown above it.
    return RepaintBoundary(
      child: _OverflowHitTestBox(overflow: overhang, child: content),
    );
  }
}

/// Renders [child] shifted `overflow` pixels above this box's own bounds and,
/// unlike a normal [RenderBox], keeps that overflowing area tappable.
///
/// Needed because the crown button pokes above the nav bar: Flutter rejects any
/// hit outside a box's size, so taps on the top of the button used to fall
/// through to whatever was behind it on the page.
class _OverflowHitTestBox extends SingleChildRenderObjectWidget {
  final double overflow;

  const _OverflowHitTestBox({required this.overflow, required Widget child})
    : super(child: child);

  @override
  _RenderOverflowHitTestBox createRenderObject(BuildContext context) =>
      _RenderOverflowHitTestBox(overflow);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOverflowHitTestBox renderObject,
  ) {
    renderObject.overflow = overflow;
  }
}

class _RenderOverflowHitTestBox extends RenderShiftedBox {
  _RenderOverflowHitTestBox(this._overflow) : super(null);

  double _overflow;
  double get overflow => _overflow;
  set overflow(double value) {
    if (_overflow == value) return;
    _overflow = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
        maxHeight: double.infinity,
      ),
      parentUsesSize: true,
    );
    (child.parentData as BoxParentData).offset = Offset(0, -_overflow);
    size = constraints.constrain(
      Size(child.size.width, child.size.height - _overflow),
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    // Intentionally skips the `size.contains(position)` guard in
    // RenderBox.hitTest so hits above this box reach the child.
    return result.addWithPaintOffset(
      offset: Offset(0, -_overflow),
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) =>
          child.hitTest(result, position: transformed),
    );
  }
}
