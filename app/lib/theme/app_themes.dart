import 'package:flutter/material.dart';

enum AppThemePreset { departureBoard, transitMap, softTint, editorial }

extension AppThemePresetLabel on AppThemePreset {
  String get storageKey {
    switch (this) {
      case AppThemePreset.departureBoard:
        return 'board';
      case AppThemePreset.transitMap:
        return 'transit_map';
      case AppThemePreset.softTint:
        return 'soft_tint';
      case AppThemePreset.editorial:
        return 'editorial';
    }
  }
}

AppThemePreset presetFromKey(String? raw) {
  switch (raw) {
    case 'board':
      return AppThemePreset.departureBoard;
    case 'transit_map':
      return AppThemePreset.transitMap;
    case 'editorial':
      return AppThemePreset.editorial;
    case 'soft_tint':
    default:
      return AppThemePreset.softTint;
  }
}

class AppThemeTokens {
  final Color background;
  final Color surface;
  final Color ink;
  final Color inkSecondary;
  final Color inkFaint;
  final Color accent;
  final Color line;
  final double radius;
  final bool monoNumerals;
  final Brightness brightness;

  const AppThemeTokens({
    required this.background,
    required this.surface,
    required this.ink,
    required this.inkSecondary,
    required this.inkFaint,
    required this.accent,
    required this.line,
    required this.radius,
    required this.monoNumerals,
    required this.brightness,
  });

  bool get isDark => brightness == Brightness.dark;
  Radius get cardRadius => Radius.circular(radius);
  double get buttonRadius => (radius - 2).clamp(4, 24);
  Color get accentSoft => Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.22 : 0.10),
        surface,
      );
}

AppThemeTokens themeTokens(AppThemePreset preset, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  switch (preset) {
    case AppThemePreset.departureBoard:
      return AppThemeTokens(
        background: dark ? const Color(0xFF0C0F12) : const Color(0xFFF3F4F6),
        surface: dark ? const Color(0xFF14181D) : Colors.white,
        ink: dark ? const Color(0xFFF2F5F7) : const Color(0xFF0C0F12),
        inkSecondary:
            dark ? const Color(0xFFB9C3CE) : const Color(0xFF4C5663),
        inkFaint: dark ? const Color(0xFF7E8B99) : const Color(0xFF8A94A1),
        accent: dark ? const Color(0xFFFFB020) : const Color(0xFF8A5A00),
        line: dark ? const Color(0xFF232A32) : const Color(0xFFDDE1E6),
        radius: 6,
        monoNumerals: true,
        brightness: brightness,
      );
    case AppThemePreset.transitMap:
      return AppThemeTokens(
        background: dark ? const Color(0xFF0A0A0A) : Colors.white,
        surface: dark ? const Color(0xFF141414) : Colors.white,
        ink: dark ? const Color(0xFFFAFAFA) : const Color(0xFF0A0A0A),
        inkSecondary:
            dark ? const Color(0xFFB5B5B5) : const Color(0xFF6B7280),
        inkFaint: dark ? const Color(0xFF7A7A7A) : const Color(0xFF9CA3AF),
        accent: dark ? const Color(0xFFFAFAFA) : const Color(0xFF0A0A0A),
        line: dark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5E5),
        radius: 2,
        monoNumerals: true,
        brightness: brightness,
      );
    case AppThemePreset.softTint:
      return AppThemeTokens(
        background: dark ? const Color(0xFF141220) : const Color(0xFFFAF8F5),
        surface: dark ? const Color(0xFF1D1A2B) : Colors.white,
        ink: dark ? const Color(0xFFF3F1FA) : const Color(0xFF1B1B2F),
        inkSecondary:
            dark ? const Color(0xFFB9B4CB) : const Color(0xFF6E6A75),
        inkFaint: dark ? const Color(0xFF8B87A0) : const Color(0xFF8B8794),
        accent: dark ? const Color(0xFF8B96FF) : const Color(0xFF5B6CFF),
        line: dark ? const Color(0xFF2A2640) : const Color(0xFFEDE9E2),
        radius: 24,
        monoNumerals: false,
        brightness: brightness,
      );
    case AppThemePreset.editorial:
      return AppThemeTokens(
        background: dark ? const Color(0xFF17150F) : const Color(0xFFF7F3EC),
        surface: dark ? const Color(0xFF201D16) : const Color(0xFFFFFDF8),
        ink: dark ? const Color(0xFFF2EDE2) : const Color(0xFF1C1A17),
        inkSecondary:
            dark ? const Color(0xFFC4BCAE) : const Color(0xFF6E675C),
        inkFaint: dark ? const Color(0xFF8E867A) : const Color(0xFF8A8378),
        accent: dark ? const Color(0xFF9CC0AC) : const Color(0xFF1F4D3A),
        line: dark ? const Color(0xFF332E24) : const Color(0xFFE4DCCE),
        radius: 4,
        monoNumerals: false,
        brightness: brightness,
      );
  }
}

ThemeData buildAppTheme(AppThemePreset preset, Brightness brightness) {
  final t = themeTokens(preset, brightness);
  final scheme = ColorScheme.fromSeed(
    seedColor: t.accent,
    brightness: brightness,
  ).copyWith(
    primary: t.accent,
    onPrimary: t.isDark && preset == AppThemePreset.departureBoard
        ? const Color(0xFF0C0F12)
        : (preset == AppThemePreset.transitMap && !t.isDark
            ? Colors.white
            : (t.isDark ? const Color(0xFF0C0F12) : Colors.white)),
    surface: t.surface,
    onSurface: t.ink,
    surfaceContainerHighest: t.isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.06), t.surface)
        : const Color(0xFFF4F6FA),
    outlineVariant: t.line,
  );

  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.background,
    canvasColor: t.background,
    cardColor: t.surface,
    dividerColor: t.line,
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: t.ink,
      titleTextStyle: TextStyle(
        color: t.ink,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.4,
        height: 1.0,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.15,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.15,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      bodyLarge:
          TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w500),
      bodyMedium:
          TextStyle(fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w500),
      bodySmall:
          TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w500),
      labelLarge: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      labelMedium: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelSmall: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      color: t.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(t.cardRadius),
        side: BorderSide(color: t.line),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: t.accent,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
        side: BorderSide(color: t.line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.buttonRadius),
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.buttonRadius),
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.buttonRadius),
        borderSide: BorderSide(color: t.accent, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: TextStyle(
        color: t.inkFaint,
        fontWeight: FontWeight.w500,
        fontSize: 13.5,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.accentSoft,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.buttonRadius - 4),
      ),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 11.5,
        color: t.inkSecondary,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.isDark ? t.ink : const Color(0xFF0E1521),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.buttonRadius),
      ),
      contentTextStyle: TextStyle(
        color: t.isDark ? t.surface : Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      indicatorColor: t.accentSoft,
      elevation: 0,
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: states.contains(WidgetState.selected) ? t.accent : t.inkFaint,
        ),
      ),
    ),
  );

  return base;
}

List<BoxShadow> themeShadows(AppThemeTokens t, {bool prominent = false}) {
  if (!prominent) return const <BoxShadow>[];
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: t.isDark ? 0.35 : 0.07),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}
