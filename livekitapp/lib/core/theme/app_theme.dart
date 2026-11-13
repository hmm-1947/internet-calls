import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  static const brand = Color(0xFF12A044);
  static const brandDark = Color(0xFF0B7A33);
  static const online = Color(0xFF22C55E);
  static const offline = Color(0xFF9CA3AF);
  static const gold = Color(0xFFE8B93A);
  static const danger = Color(0xFFE5484D);
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg;
  final Color card;
  final Color card2;
  final Color border;
  final Color overlay;
  final Color text;
  final Color textSecondary;
  final Color muted;
  final Color faint;
  final Color brandTint;

  const AppPalette({
    required this.bg,
    required this.card,
    required this.card2,
    required this.border,
    required this.overlay,
    required this.text,
    required this.textSecondary,
    required this.muted,
    required this.faint,
    required this.brandTint,
  });

  static const light = AppPalette(
    bg: Color(0xFFFFFFFF),
    card: Color(0xFFF3F4F6),
    card2: Color(0xFFE9ECEF),
    border: Color(0xFFE5E7EB),
    overlay: Color(0x0F000000),
    text: Color(0xFF111111),
    textSecondary: Color(0xFF374151),
    muted: Color(0xFF6B7280),
    faint: Color(0xFF9CA3AF),
    brandTint: Color(0xFFDDF3E4),
  );

  static const dark = AppPalette(
    bg: Color(0xFF0E1210),
    card: Color(0xFF171C19),
    card2: Color(0xFF212823),
    border: Color(0x1FFFFFFF),
    overlay: Color(0x1AFFFFFF),
    text: Color(0xFFF3F6F4),
    textSecondary: Color(0xFFC9D1CC),
    muted: Color(0xFF9AA39E),
    faint: Color(0xFF6B746F),
    brandTint: Color(0xFF173824),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? card,
    Color? card2,
    Color? border,
    Color? overlay,
    Color? text,
    Color? textSecondary,
    Color? muted,
    Color? faint,
    Color? brandTint,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      card2: card2 ?? this.card2,
      border: border ?? this.border,
      overlay: overlay ?? this.overlay,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      brandTint: brandTint ?? this.brandTint,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      card2: Color.lerp(card2, other.card2, t)!,
      border: Color.lerp(border, other.border, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      brandTint: Color.lerp(brandTint, other.brandTint, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppPalette get c => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  static ThemeData get light => _build(Brightness.light, AppPalette.light);
  static ThemeData get dark => _build(Brightness.dark, AppPalette.dark);

  static SystemUiOverlayStyle overlay(Brightness b) {
    final dark = b == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: dark ? AppPalette.dark.bg : AppPalette.light.bg,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    );
  }

  static ThemeData _build(Brightness b, AppPalette p) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: b,
    ).copyWith(
      primary: AppColors.brand,
      onPrimary: Colors.white,
      secondary: AppColors.brand,
      onSecondary: Colors.white,
      primaryContainer: p.brandTint,
      onPrimaryContainer: b == Brightness.dark
          ? const Color(0xFFBFF0CF)
          : AppColors.brandDark,
      surface: p.bg,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
      surfaceContainerLowest: p.bg,
      surfaceContainerLow: p.card,
      surfaceContainer: p.card,
      surfaceContainerHigh: p.card2,
      surfaceContainerHighest: p.card2,
      outline: p.border,
      outlineVariant: p.border,
      error: AppColors.danger,
    );
    final radius = BorderRadius.circular(14);
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      cardColor: p.card,
      dividerColor: p.border,
      extensions: [p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlay(b),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: p.border, space: 1),
      iconTheme: IconThemeData(color: p.text),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        hintStyle: TextStyle(color: p.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.faint, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.faint, width: 1),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.brand),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brand,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : p.faint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.brand : p.card2,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: b == Brightness.dark ? p.card2 : const Color(0xFF1F2937),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.brand,
        selectionHandleColor: AppColors.brand,
      ),
    );
  }
}
