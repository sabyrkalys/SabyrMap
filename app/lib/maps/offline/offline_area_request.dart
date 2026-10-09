import 'package:app/maps/file_maps/map_bounds.dart';

/// Область для сохранения офлайн.
class OfflineAreaRequest {
  const OfflineAreaRequest({
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.sourceIds,
    this.estimatedTileCount = 0,
    this.estimatedBytes = 0,
  });

  final MapBounds bounds;
  final int minZoom;
  final int maxZoom;
  final List<String> sourceIds;

  /// Всех источников вместе.
  final int estimatedTileCount;
  final int estimatedBytes;
}
