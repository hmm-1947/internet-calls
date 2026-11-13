import 'package:flutter/material.dart';
import 'package:livekitapp/core/theme/app_theme.dart';

class AppSearchBar extends StatefulWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final TextEditingController? controller;

  const AppSearchBar({
    super.key,
    required this.hintText,
    this.onChanged,
    this.focusNode,
    this.controller,
  });

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant AppSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownNode)?.removeListener(_onFocus);
      _node.addListener(_onFocus);
    }
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _node.hasFocus;
    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: context.c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused ? AppColors.brand : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: TextField(
        focusNode: _node,
        controller: widget.controller,
        style: TextStyle(color: context.c.text),
        cursorColor: AppColors.brand,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(color: context.c.muted),
          prefixIcon: Icon(Icons.search, color: context.c.muted),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
