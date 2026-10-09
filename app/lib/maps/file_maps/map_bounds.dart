import 'dart:math';

import 'package:app/landmarks/models/landmark_location.dart';

/// Прямоугольные границы в градусах (через ±180° не переходят).
class MapBounds {
  const MapBounds({required this.northLat, required this.southLat, required this.westLon, required this.eastLon});

  final double northLat;
  final double southLat;
  final double westLon;
  final double eastLon;

  /// Север не южнее юга, восток не западнее запада, значения в пределах.
  bool get isValid =>
      northLat >= southLat &&
      eastLon >= westLon &&
      northLat <= 90 &&
      southLat >= -90 &&
      westLon >= -180 &&
      eastLon <= 180;

  /// Нулевая площадь.
  bool get isEmpty => northLat == southLat || eastLon == westLon;

  bool contains(LandmarkLocation p) =>
      p.latitude <= northLat && p.latitude >= southLat && p.longitude >= westLon && p.longitude <= eastLon;

  /// Есть общие точки (касание краями — тоже).
  bool intersects(MapBounds other) =>
      isValid &&
      other.isValid &&
      other.westLon <= eastLon &&
      other.eastLon >= westLon &&
      other.southLat <= northLat &&
      other.northLat >= southLat;

  MapBounds union(MapBounds other) => MapBounds(
    northLat: max(northLat, other.northLat),
    southLat: min(southLat, other.southLat),
    westLon: min(westLon, other.westLon),
    eastLon: max(eastLon, other.eastLon),
  );

  /// Общая часть; нет пересечения или границы неверные — null.
  MapBounds? intersection(MapBounds other) {
    if (!intersects(other)) return null;
    return MapBounds(
      northLat: min(northLat, other.northLat),
      southLat: max(southLat, other.southLat),
      westLon: max(westLon, other.westLon),
      eastLon: min(eastLon, other.eastLon),
    );
  }

  double get areaSquareDegrees => isValid ? (northLat - southLat) * (eastLon - westLon) : 0;

  Map<String, Object?> toJson() => {'north': northLat, 'south': southLat, 'west': westLon, 'east': eastLon};

  factory MapBounds.fromJson(Map<String, dynamic> json) => MapBounds(
    northLat: (json['north'] as num).toDouble(),
    southLat: (json['south'] as num).toDouble(),
    westLon: (json['west'] as num).toDouble(),
    eastLon: (json['east'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is MapBounds &&
      other.northLat == northLat &&
      other.southLat == southLat &&
      other.westLon == westLon &&
      other.eastLon == eastLon;

  @override
  int get hashCode => Object.hash(northLat, southLat, westLon, eastLon);

  @override
  String toString() => 'MapBounds(N $northLat, S $southLat, W $westLon, E $eastLon)';
}
