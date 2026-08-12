import 'package:flutter/material.dart';

class PillMessage {
  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? color,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _current?.remove();
    _current = null;

    final entry = OverlayEntry(
      builder: (context) => _PillMessageWidget(
        message: message,
        icon: icon,
        color: color ?? const Color(0xFF1F2937),
        onDismissed: () {
          _current?.remove();
          _current = null;
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);

    Future.delayed(duration, () {
      if (_current == entry) {
        entry.remove();
        _current = null;
      }
    });
  }

  static void showError(BuildContext context, String message) {
    show(
      context,
      message,
      icon: Icons.error_outline,
      color: const Color(0xFFB91C1C),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    show(
      context,
      message,
      icon: Icons.check_circle_outline,
      color: const Color(0xFF15803D),
    );
  }
}

class _PillMessageWidget extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Color color;
  final VoidCallback onDismissed;

  const _PillMessageWidget({
    required this.message,
    required this.icon,
    required this.color,
    required this.onDismissed,
  });

  @override
  State<_PillMessageWidget> createState() => _PillMessageWidgetState();
}

class _PillMessageWidgetState extends State<_PillMessageWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      bottom: bottomPadding + 12,
      left: 16,
      right: 16,
      child: SafeArea(
        top: false,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: widget.onDismissed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
