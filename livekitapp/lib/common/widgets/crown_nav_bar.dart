import 'dart:ui';
import 'package:flutter/material.dart';

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
      widget.onDestinationSelected(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFE53950);
    const inactiveColor = Colors.white70;
    final itemCount = widget.icons.length;

    Widget buildItem(int i) {
      final selected = widget.selectedIndex == i;
      final color = selected ? activeColor : inactiveColor;
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

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: 78 + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0x400F1A2E),
                border: Border(top: BorderSide(color: Color(0x55FFFFFF))),
              ),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
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
                                    color: const Color.fromARGB(
                                      51,
                                      255,
                                      124,
                                      141,
                                    ),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: const Color.fromARGB(
                                        83,
                                        255,
                                        126,
                                        126,
                                      ),
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
              // Keeps the same amount of the button poking above the bar
              // regardless of size (60px button pokes ~38px above, so scale
              // the offset off that reference instead of a fixed -22).
              top: -(widget.crownSize - 42),
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: widget.onCrownTap,
                  child: Container(
                    width: widget.crownSize,
                    height: widget.crownSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.crownImageAsset == null
                          ? const Color(0xFFFFC1B4)
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
                            ),
                          )
                        : Icon(
                            widget.crownIcon,
                            color: const Color(0xFF2A0A0A),
                            size: widget.crownSize * 28 / 60,
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
