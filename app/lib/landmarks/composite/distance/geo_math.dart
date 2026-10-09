import 'dart:math';

export 'bearing.dart';
export 'haversine.dart';

/// Общие константы и пересчёт углов.
abstract final class GeoMath {
  /// Средний радиус Земли, метры.
  static const double earthRadiusMeters = 6371008.8;

  static double toRadians(double degrees) => degrees * pi / 180;

  static double toDegrees(double radians) => radians * 180 / pi;
}
