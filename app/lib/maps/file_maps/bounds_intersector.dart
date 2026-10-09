import 'dart:math';

import 'package:app/landmarks/models/landmark_location.dart';

import 'map_bounds.dart';

/// Помощники для границ.
abstract final class BoundsIntersector {
  static bool boundsCoverPoint(MapBounds b, LandmarkLocation p) => b.contains(p);

  /// Наименьшие границы, вмещающие [points]. Пустой список — [ArgumentError].
  static MapBounds boundsOf(List<LandmarkLocation> points) {
    if (points.isEmpty) throw ArgumentError('no points');
    return MapBounds(
      northLat: points.map((p) => p.latitude).reduce(max),
      southLat: points.map((p) => p.latitude).reduce(min),
      westLon: points.map((p) => p.longitude).reduce(min),
      eastLon: points.map((p) => p.longitude).reduce(max),
    );
  }

  /// Шире на [margin] градусов с каждой стороны, в пределах ±90/±180.
  static MapBounds expand(MapBounds b, double margin) => MapBounds(
    northLat: min(90, b.northLat + margin),
    southLat: max(-90, b.southLat - margin),
    westLon: max(-180, b.westLon - margin),
    eastLon: min(180, b.eastLon + margin),
  );
}
