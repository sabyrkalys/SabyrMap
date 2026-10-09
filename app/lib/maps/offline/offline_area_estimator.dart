import 'package:app/maps/file_maps/map_bounds.dart';

import 'offline_area_request.dart';
import 'tile_budget.dart';

/// Оценка объёма области.
class OfflineAreaEstimator {
  const OfflineAreaEstimator({this.avgTileBytes = defaultAvgTileBytes});

  static const int defaultAvgTileBytes = 25000;

  final int avgTileBytes;

  /// Тайлы и байты. Неверный диапазон зумов или пустая область —
  /// [ArgumentError]. Decision: тайлы каждого источника качаются отдельно,
  /// поэтому число тайлов умножается на число источников.
  static OfflineAreaRequest estimate({
    required MapBounds bounds,
    required int minZoom,
    required int maxZoom,
    required List<String> sourceIds,
    int avgTileBytes = defaultAvgTileBytes,
  }) {
    if (minZoom > maxZoom) throw ArgumentError('minZoom $minZoom is above maxZoom $maxZoom');
    if (!bounds.isValid || bounds.isEmpty) throw ArgumentError('bounds are empty or invalid: $bounds');
    final perSource = TileBudget(minZoom: minZoom, maxZoom: maxZoom, bounds: bounds).estimateTileCount();
    final tiles = perSource * (sourceIds.isEmpty ? 1 : sourceIds.length);
    return OfflineAreaRequest(
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      sourceIds: List.unmodifiable(sourceIds),
      estimatedTileCount: tiles,
      estimatedBytes: tiles * avgTileBytes,
    );
  }

  /// Оценка для готового запроса с [avgTileBytes] этого оценщика.
  OfflineAreaRequest estimateRequest(OfflineAreaRequest req) => estimate(
    bounds: req.bounds,
    minZoom: req.minZoom,
    maxZoom: req.maxZoom,
    sourceIds: req.sourceIds,
    avgTileBytes: avgTileBytes,
  );
}
