import 'dart:math';

import 'package:app/landmarks/models/landmark_location.dart';

import 'geo_math.dart';

/// Азимуты, градусы [0, 360) от севера по часовой стрелке.
abstract final class Bearing {
  /// Начальный азимут из [a] на [b].
  static double fromTo(LandmarkLocation a, LandmarkLocation b) {
    final lat1 = GeoMath.toRadians(a.latitude);
    final lat2 = GeoMath.toRadians(b.latitude);
    final dLon = GeoMath.toRadians(b.longitude - a.longitude);
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return _normalize(GeoMath.toDegrees(atan2(y, x)));
  }

  /// Обратный азимут.
  static double reverse(double bearing) => _normalize(bearing + 180);

  static double _normalize(double degrees) {
    final d = degrees % 360;
    // -0.0 % 360 даёт -0.0; приводим к 0.
    return d == 0 ? 0 : d;
  }
}
