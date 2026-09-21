import 'package:flutter/material.dart';

/// Brand palette: forest-stone green (primary) and ochre (secondary/accent),
/// matching the natural, high-contrast "field tool" character described in
/// the design brief. Error red is shared with the "danger" waypoint color.
const Color _seedPrimary = Color(0xFF3F6B52);
const Color _seedSecondary = Color(0xFFC9A24B);
const Color _seedError = Color(0xFFE53935);

const double _minTapHeight = 52;

/// The only typeface used in the UI (bundled from assets/fonts, see OFL.txt).
const String appFontFamily = 'Roboto';
const List<String> appFontFamilyFallback = ['Noto Sans'];

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedPrimary,
      secondary: _seedSecondary,
      error: _seedError,
      brightness: brightness,
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: brightness,
      fontFamily: appFontFamily,
      fontFamilyFallback: appFontFamilyFallback,
    );

    return base.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
        elevation: 0,
      ),
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(_minTapHeight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(_minTapHeight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.secondary,
        foregroundColor: colorScheme.onSecondary,
        extendedTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colorScheme.primary : null,
        ),
      ),
    );
  }
}
