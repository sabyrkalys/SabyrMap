/// Пределы для составных объектов.
abstract final class CompositeValidationRules {
  static const int maxWaypointsPerSet = 10000;
  static const int maxWaypointsPerRoute = 5000;
  static const int maxSegmentsPerTrack = 1000;
  static const int maxLocationsPerSegment = 100000;
  static const int maxPolygonsPerArea = 100;
  static const int maxOutlinePointsPerPolygon = 100000;
  static const int maxHolesPerPolygon = 100;
  static const int maxNameLength = 200;

  /// Decision: у трека путевые точки ограничены как у набора.
  static const int maxWaypointsPerTrack = maxWaypointsPerSet;

  /// Минимум точек замкнутого контура при создании области.
  static const int minClosedOutlinePoints = 3;
}
