import 'package:flutter/material.dart';

/// Цвета и шрифты экрана «Локальные метки».
abstract final class ExplorerStyle {
  static const Color background = Colors.white;
  static const Color drawerBackground = Color(0xFFEEF1F5);
  static const Color divider = Color(0xFFE0E0E0);
  static const Color icon = Color(0xFF333333);
  static const Color text = Color(0xFF212121);
  static const Color secondary = Color(0xFF757575);
  static const Color accent = Color(0xFF00A38E);
  static const Color warning = Color(0xFFE65100);
  static const Color meterFill = Color(0xFF4CAF50);
  static const Color meterTrack = Color(0xFFE0E0E0);
  static const Color emptyIcon = Color(0xFFBDBDBD);

  static const TextStyle title = TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: text);
  static const TextStyle rowTitle = TextStyle(fontSize: 16, color: text);
  static const TextStyle subtitle = TextStyle(fontSize: 13, color: secondary);
  static const TextStyle small = TextStyle(fontSize: 12, color: secondary);
  static const TextStyle sectionHeader = TextStyle(fontSize: 12, color: secondary, letterSpacing: 0.5);

  static const Widget divider1 = Divider(height: 1, thickness: 1, color: divider);
}

