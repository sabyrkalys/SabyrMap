import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A group of icons in the «Иконка» sheet, shown as one accordion.
class IconCategory {
  const IconCategory({required this.id, required this.title, required this.icons});

  final String id;
  final String title;
  final List<MarkerIcon> icons;
}

/// An icon a waypoint can be drawn with.
class MarkerIcon {
  const MarkerIcon({required this.id, required this.label, this.icon, this.assetPath, this.fileName});

  /// Ids of the user's own icon files start with this.
  static const filePrefix = 'file:';

  final String id;
  final String label;

  /// Null draws a filled circle (or, for [noneOption], nothing).
  final IconData? icon;

  /// Path of an SVG/PNG picture to draw instead of [icon].
  final String? assetPath;

  /// For the user's own icon files: the file name the map draws the
  /// waypoint with.
  final String? fileName;

  bool get isFile => fileName != null;
}

/// «Нет»: the waypoint keeps the standard marker.
const noneOption = MarkerIcon(id: 'none', label: 'Нет');

/// Built-in categories of the «Иконка» sheet, before the device folder's.
///
/// Decision: empty -- the map symbols live in the device icon folder (each
/// subfolder a category), where the map can draw them; the former sample
/// glyphs were removed. Tests supply their own set.
final builtInIconCategoriesProvider = Provider<List<IconCategory>>((ref) => const []);
