import 'package:app/landmarks/composite/distance/geo_math.dart';
import 'package:app/landmarks/models/landmark_location.dart';

import 'target_info.dart';

/// Расстояние, азимуты, перепад высот, уклон и время до цели.
abstract final class TargetCalculator {
  static TargetInfo compute({
    required LandmarkLocation source,
    required LandmarkLocation target,
    double? sourceElevation,
    double? targetElevation,
    double? speedMps,
  }) {
    final distance = Haversine.distance(source, target);
    final azimuth = Bearing.fromTo(source, target);
    final diff = sourceElevation != null && targetElevation != null ? targetElevation - sourceElevation : null;
    return TargetInfo(
      distanceMeters: distance,
      azimuthDeg: azimuth,
      reverseAzimuthDeg: Bearing.reverse(azimuth),
      elevationDiffMeters: diff,
      slopePercent: diff != null && distance > 0 ? 100 * diff / distance : null,
      etaSeconds: speedMps != null && speedMps > 0 ? (distance / speedMps).round() : null,
      speedMps: speedMps,
    );
  }

  /// Высота точки из её значений, метры.
  static double? elevationOf(LandmarkLocation location) =>
      switch (location.valueOf(LocationValueType.elevation)?.value) {
        final int raw => raw / 1000,
        _ => null,
      };
}
