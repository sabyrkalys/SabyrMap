import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Typography for menu panels: section headers and menu items.
///
/// Light-theme colors are fixed by the design spec; in dark theme they are
/// derived from the [ColorScheme] until dark values are specified.
class AppTextStyles {
  AppTextStyles._();

  static const Color _lightSectionHeader = Color(0xFF8A8A8E);
  static const Color _lightMenuItem = Color(0xFF16181A);
  static const Color _lightMenuItemDisabled = Color(0xFFA0A3A8);

  /// Section title: Roboto Medium 500, 12, +0.08em tracking. Callers must
  /// render the text UPPERCASE themselves.
  static TextStyle sectionHeader(BuildContext context) {
    return TextStyle(
      fontFamily: appFontFamily,
      fontFamilyFallback: appFontFamilyFallback,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      letterSpacing: 12 * 0.08,
      color: _isLight(context) ? _lightSectionHeader : Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  /// Menu item: Roboto Regular 400, 16, line height 1.3, sentence case.
  static TextStyle menuItem(BuildContext context) {
    return TextStyle(
      fontFamily: appFontFamily,
      fontFamilyFallback: appFontFamilyFallback,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      height: 1.3,
      color: _isLight(context) ? _lightMenuItem : Theme.of(context).colorScheme.onSurface,
    );
  }

  /// Same as [menuItem] with the disabled color. The item's icon must use the
  /// same color.
  static TextStyle menuItemDisabled(BuildContext context) {
    return menuItem(context).copyWith(
      color: _isLight(context)
          ? _lightMenuItemDisabled
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
    );
  }

  static bool _isLight(BuildContext context) => Theme.of(context).brightness == Brightness.light;
}
