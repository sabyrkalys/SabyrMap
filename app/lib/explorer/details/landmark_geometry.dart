import 'package:app/landmarks/models/landmark_file.dart';

/// Точки объекта для показа на карте и в превью.
abstract final class LandmarkGeometry {
  /// Все точки объекта: точка, точки набора и маршрута, сегменты трека,
  /// контуры области. У файла меток — пусто.
  static List<LandmarkLocation> pointsOf(LandmarkObject? object) => switch (object) {
    final WaypointObject o => [o.location],
    final SetObject o => [for (final w in o.waypoints) w.location],
    final RouteObject o => [for (final w in o.waypoints) w.location],
    final TrackObject o => [
      for (final s in o.segments) ...s.locations,
      if (o.segments.every((s) => s.locations.isEmpty)) ...[for (final w in o.waypoints) w.location],
    ],
    final AreaObject o => [for (final poly in o.polygons) ...poly.outline],
    _ => const [],
  };

  /// Середина охватывающего прямоугольника; null — точек нет.
  static ({double latitude, double longitude})? centerOf(LandmarkObject? object) {
    final points = pointsOf(object);
    if (points.isEmpty) return null;
    var minLat = points.first.latitude, maxLat = minLat;
    var minLon = points.first.longitude, maxLon = minLon;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    return (latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2);
  }
}
