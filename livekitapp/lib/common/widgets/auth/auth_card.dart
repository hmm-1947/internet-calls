import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// A themed rounded card used across the auth flows (login / register /
/// forgot password) to give OTP and form screens a consistent, polished
/// look matching the app's black + red palette.
class AuthCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const AuthCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: context.c.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.brand.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withOpacity(0.10),
            blurRadius: 28,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brand.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.brand, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.c.text,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.c.muted, fontSize: 13.5),
            ),
          ],
          const SizedBox(height: 26),
          ...children,
        ],
      ),
    );
  }
}

/// A text field styled to match [AuthCard], with a slightly translucent
/// fill instead of a plain outline so it reads well on the dark card.
class AuthTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final double? letterSpacing;
  final double? fontSize;
  final int? maxLength;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.letterSpacing,
    this.fontSize,
    this.maxLength,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: widget.obscureText && _obscured,
      keyboardType: widget.keyboardType,
      textAlign: widget.textAlign,
      maxLength: widget.maxLength,
      style: TextStyle(
        color: context.c.text,
        letterSpacing: widget.letterSpacing,
        fontSize: widget.fontSize,
        fontWeight: widget.letterSpacing != null ? FontWeight.w600 : null,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(color: context.c.muted),
        counterText: '',
        filled: true,
        fillColor: context.c.card,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: context.c.faint, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        suffixIcon: widget.obscureText
            ? IconButton(
                icon: Icon(
                  _obscured ? Icons.visibility_off : Icons.visibility,
                  color: context.c.muted,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
      ),
    );
  }
}
