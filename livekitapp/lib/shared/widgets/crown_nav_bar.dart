import 'dart:ui';
import 'package:flutter/material.dart';

class CrownNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> icons;
  final List<String> labels;
  final VoidCallback onCrownTap;
  final bool showCrown;

  const CrownNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.icons,
    required this.labels,
    required this.onCrownTap,
    this.showCrown = true,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFE53950);
    const inactiveColor = Colors.white70;
    final itemCount = icons.length;

    Widget buildItem(int i) {
      final selected = selectedIndex == i;
      final color = selected ? activeColor : inactiveColor;
      return Expanded(
        child: InkWell(
          onTap: () => onDestinationSelected(i),
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(color: color, size: 22),
                  child: icons[i],
                ),
                const SizedBox(height: 4),
                Text(labels[i], style: TextStyle(color: color, fontSize: 11)),
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
                          final slotCount = showCrown
                              ? itemCount + 1
                              : itemCount;
                          final slotWidth = constraints.maxWidth / slotCount;
                          final crownSlot = itemCount ~/ 2;
                          final slotIndex =
                              showCrown && selectedIndex >= crownSlot
                              ? selectedIndex + 1
                              : selectedIndex;
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
                                  if (showCrown)
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
          if (showCrown)
            Positioned(
              top: -22,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onCrownTap,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFC1B4),
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withOpacity(0.5),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.emoji_events,
                      color: Color(0xFF2A0A0A),
                      size: 28,
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
