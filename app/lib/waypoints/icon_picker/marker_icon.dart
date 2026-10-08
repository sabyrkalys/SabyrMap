import 'package:flutter/material.dart';

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

/// Built-in categories, a sample to show how the sheet works; the real set
/// comes in a later iteration.
const sampleCategories = <IconCategory>[
  IconCategory(
    id: 'marker',
    title: 'МЕТКА',
    icons: [
      MarkerIcon(id: 'marker-default', label: 'Default', icon: Icons.place),
      MarkerIcon(id: 'marker-star', label: 'Star', icon: Icons.star),
    ],
  ),
  IconCategory(
    id: 'tourism',
    title: 'ТУРИЗМ',
    icons: [
      MarkerIcon(id: 'tourism-camp', label: 'Camp', icon: Icons.cabin),
      MarkerIcon(id: 'tourism-view', label: 'Viewpoint', icon: Icons.landscape),
      MarkerIcon(id: 'tourism-museum', label: 'Museum', icon: Icons.museum),
    ],
  ),
  IconCategory(
    id: 'transport',
    title: 'ТРАНСПОРТ',
    icons: [
      MarkerIcon(id: 'transport-parking', label: 'Parking', icon: Icons.local_parking),
      MarkerIcon(id: 'transport-fuel', label: 'Fuel', icon: Icons.local_gas_station),
    ],
  ),
  IconCategory(
    id: 'food',
    title: 'ПИТАНИЕ',
    icons: [
      MarkerIcon(id: 'food-cafe', label: 'Cafe', icon: Icons.local_cafe),
      MarkerIcon(id: 'food-restaurant', label: 'Restaurant', icon: Icons.restaurant),
    ],
  ),
  IconCategory(
    id: 'structures',
    title: 'СООРУЖЕНИЯ',
    icons: [
      MarkerIcon(id: 'struct-manmade', label: 'Man made'),
      MarkerIcon(id: 'struct-bunker', label: 'Bunker', icon: Icons.shield),
      MarkerIcon(id: 'struct-checkpoint', label: 'Checkpoint', icon: Icons.security),
      MarkerIcon(id: 'struct-chimney', label: 'Chimney', icon: Icons.factory),
      MarkerIcon(id: 'struct-crane', label: 'Crane', icon: Icons.precision_manufacturing),
      MarkerIcon(id: 'struct-military', label: 'Military', icon: Icons.military_tech),
      MarkerIcon(id: 'struct-mine', label: 'Mine', icon: Icons.construction),
    ],
  ),
  IconCategory(
    id: 'nature',
    title: 'ПРИРОДА',
    icons: [
      MarkerIcon(id: 'nature-tree', label: 'Tree', icon: Icons.park),
      MarkerIcon(id: 'nature-water', label: 'Water', icon: Icons.water),
    ],
  ),
];
