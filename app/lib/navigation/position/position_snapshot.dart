import 'package:app/landmarks/models/landmark_location.dart';

/// Положение устройства в момент времени.
class PositionSnapshot {
  const PositionSnapshot({required this.location, this.headingDeg, this.speedMps, this.timestampMs, this.accuracyM});

  final LandmarkLocation location;

  /// Курс устройства, градусы от севера.
  final double? headingDeg;
  final double? speedMps;

  /// Время замера, Unix ms.
  final int? timestampMs;

  /// Точность, метры.
  final double? accuracyM;

  /// Координаты в допустимых пределах и не NaN.
  bool get isValid {
    final lat = location.latitude;
    final lon = location.longitude;
    return lat.isFinite && lon.isFinite && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }
}
