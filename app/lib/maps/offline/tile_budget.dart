import 'dart:math';

import 'package:app/maps/file_maps/map_bounds.dart';

/// Сколько тайлов Web Mercator покрывает область на диапазоне зумов.
class TileBudget {
  TileBudget({required this.minZoom, required this.maxZoom, required this.bounds}) {
    if (minZoom < 0 || maxZoom > maxSupportedZoom || minZoom > maxZoom) {
      throw ArgumentError('Zoom range must be 0 <= minZoom <= maxZoom <= $maxSupportedZoom, got $minZoom..$maxZoom');
    }
  }

  static const int maxSupportedZoom = 24;

  /// Предел широты Web Mercator.
  static const double maxLatitude = 85.05112878;

  final int minZoom;
  final int maxZoom;
  final MapBounds bounds;

  /// Сумма по зумам числа тайлов, задетых областью. Края области на
  /// границе тайла соседний тайл не захватывают. Пустая область — 0.
  int estimateTileCount() {
    if (!bounds.isValid || bounds.isEmpty) return 0;
    var total = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final r = tileRange(z);
      total += (r.maxX - r.minX + 1) * (r.maxY - r.minY + 1);
    }
    return total;
  }

  /// Номера тайлов области на зуме [z].
  ({int minX, int maxX, int minY, int maxY}) tileRange(int z) {
    final n = 1 << z;
    double x(double lon) => (lon + 180) / 360 * n;
    double y(double lat) {
      final l = lat.clamp(-maxLatitude, maxLatitude) * pi / 180;
      return (1 - log(tan(l) + 1 / cos(l)) / pi) / 2 * n;
    }

    int first(double v) => v.floor().clamp(0, n - 1);
    int last(double v) => (v.ceil() - 1).clamp(0, n - 1);
    return (
      minX: first(x(bounds.westLon)),
      maxX: max(first(x(bounds.westLon)), last(x(bounds.eastLon))),
      minY: first(y(bounds.northLat)),
      maxY: max(first(y(bounds.northLat)), last(y(bounds.southLat))),
    );
  }
}
