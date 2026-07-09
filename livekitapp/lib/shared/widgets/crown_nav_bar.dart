import 'package:flutter/material.dart';

class CrownNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> icons;
  final List<String> labels;
  final VoidCallback onCrownTap;

  const CrownNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.icons,
    required this.labels,
    required this.onCrownTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFE53950);
    const inactiveColor = Colors.white70;
    const barColor = Color(0xFF0F1A2E);

    Widget buildItem(int i) {
      final selected = selectedIndex == i;
      final color = selected ? activeColor : inactiveColor;
      return Expanded(
        child: InkWell(
          onTap: () => onDestinationSelected(i),
          child: Column(
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
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      color: barColor,
      padding: EdgeInsets.only(bottom: bottomInset),
      height: 78 + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: const BoxDecoration(color: barColor),
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
