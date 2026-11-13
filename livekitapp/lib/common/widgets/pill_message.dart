import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

enum PillKind { info, success, error }

class PillMessage {
  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? color,
    PillKind kind = PillKind.info,
    Duration duration = const Duration(seconds: 3),
    double bottomOffset = 0,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _current?.remove();
    _current = null;

    final entry = OverlayEntry(
      builder: (context) => _PillMessageWidget(
        message: message,
        icon: icon,
        color: color,
        kind: kind,
        bottomOffset: bottomOffset,
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

  static void showError(
    BuildContext context,
    String message, {
    double bottomOffset = 0,
  }) {
    show(
      context,
      message,
      icon: Icons.error_outline,
      kind: PillKind.error,
      bottomOffset: bottomOffset,
    );
  }

  static void showSuccess(
    BuildContext context,
    String message, {
    double bottomOffset = 0,
  }) {
    show(
      context,
      message,
      icon: Icons.check_circle_outline,
      kind: PillKind.success,
      bottomOffset: bottomOffset,
    );
  }
}

class _PillMessageWidget extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Color? color;
  final PillKind kind;
  final double bottomOffset;
  final VoidCallback onDismissed;

  const _PillMessageWidget({
    required this.message,
    required this.icon,
    required this.color,
    required this.kind,
    required this.bottomOffset,
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final p = context.c;
    final Color bg;
    final Color fg;
    final Color accent;
    final Color borderColor;
    switch (widget.kind) {
      case PillKind.success:
        bg = p.brandTint;
        fg = AppColors.brandDark;
        accent = AppColors.brand;
        borderColor = AppColors.brand.withValues(alpha: 0.35);
        break;
      case PillKind.error:
        bg = const Color(0xFFFDECEC);
        fg = const Color(0xFF9B1C1C);
        accent = AppColors.danger;
        borderColor = AppColors.danger.withValues(alpha: 0.35);
        break;
      case PillKind.info:
        bg = p.bg;
        fg = p.text;
        accent = AppColors.brand;
        borderColor = p.border;
        break;
    }
    final clearance = keyboardInset > 0
        ? keyboardInset + widget.bottomOffset + 12
        : widget.bottomOffset + bottomPadding + 12;
    return Positioned(
      bottom: clearance,
      left: 16,
      right: 16,
      child: SafeArea(
        top: false,
        bottom: false,
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
                      color: widget.color ?? bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: accent, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: fg,
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

