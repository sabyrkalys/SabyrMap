import 'package:app/landmarks/models/landmark_location.dart';

/// Отрезок измерения между соседними точками.
class MeasureSegment {
  const MeasureSegment({
    required this.from,
    required this.to,
    required this.distanceMeters,
    required this.azimuthDeg,
    required this.segmentColor,
  });

  final LandmarkLocation from;
  final LandmarkLocation to;
  final double distanceMeters;
  final double azimuthDeg;

  /// Цвет ARGB по азимуту.
  final int segmentColor;
}
