import '../../config/storage_paths.dart';

/// A group a new waypoint can be saved into, as listed in the «Путевая
/// точка» dialog.
class MarkerGroup {
  const MarkerGroup({
    required this.id,
    required this.title,
    this.subtitle,
    this.hasSectionDivider = false,
    this.sectionLabel,
  });

  static const unsortedId = 'unsorted';
  static const myMarkersId = 'my-markers';

  /// Not a group to save into: opens the list of all waypoints.
  static const allId = 'all';

  final String id;
  final String title;

  /// Where the group is stored; null for «Все метки».
  final String? subtitle;

  /// Draws a line above this item: the first item of a section.
  final bool hasSectionDivider;

  /// The section's name above this item («МОИ МЕТКИ»), if it starts one.
  final String? sectionLabel;
}

/// The built-in groups, their paths from [StoragePaths].
List<MarkerGroup> get builtInMarkerGroups => [
  MarkerGroup(id: MarkerGroup.unsortedId, title: 'Несортированные метки', subtitle: '${StoragePaths.unsorted}/'),
  MarkerGroup(
    id: MarkerGroup.myMarkersId,
    title: 'Мои метки',
    subtitle: '${StoragePaths.landmarks}/',
    hasSectionDivider: true,
    sectionLabel: 'Мои метки',
  ),
  const MarkerGroup(id: MarkerGroup.allId, title: 'Все метки'),
];
