import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

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

    Widget buildItem(int i) {
      final selected = selectedIndex == i;
      final color = selected ? activeColor : inactiveColor;
      final itemContent = SizedBox(
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
      );
      return Expanded(
        child: InkWell(
          onTap: () => onDestinationSelected(i),
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 56,
            decoration: BoxDecoration(
              color: selected
                  ? const Color.fromARGB(51, 255, 124, 141)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: selected
                  ? Border.all(
                      color: const Color.fromARGB(83, 255, 126, 126),
                      width: 1,
                    )
                  : null,
            ),
            child: Center(child: itemContent),
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
                      child: Row(
                        children: [
                          buildItem(0),
                          buildItem(1),
                          const Expanded(child: SizedBox()),
                          buildItem(2),
                          buildItem(3),
                        ],
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
