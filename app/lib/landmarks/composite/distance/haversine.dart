import 'dart:math';

import 'package:app/landmarks/models/landmark_location.dart';

import 'geo_math.dart';

/// Расстояния по большому кругу (формула гаверсинусов), метры.
abstract final class Haversine {
  /// Между двумя точками.
  static double distance(LandmarkLocation a, LandmarkLocation b) =>
      distanceDegrees(a.latitude, a.longitude, b.latitude, b.longitude);

  /// Между двумя точками, заданными в градусах.
  static double distanceDegrees(double lat1, double lon1, double lat2, double lon2) {
    final dLat = GeoMath.toRadians(lat2 - lat1);
    final dLon = GeoMath.toRadians(lon2 - lon1);
    final h =
        pow(sin(dLat / 2), 2) + cos(GeoMath.toRadians(lat1)) * cos(GeoMath.toRadians(lat2)) * pow(sin(dLon / 2), 2);
    return 2 * GeoMath.earthRadiusMeters * asin(min(1.0, sqrt(h)));
  }

  /// Длина ломаной через [points]; [close] — плюс отрезок от последней
  /// точки к первой.
  static double totalDistance(List<LandmarkLocation> points, {bool close = false}) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distance(points[i - 1], points[i]);
    }
    if (close && points.length > 2) total += distance(points.last, points.first);
    return total;
  }

  /// Длина одного сегмента трека.
  static double segmentDistance(List<LandmarkLocation> locations) => totalDistance(locations);
}
