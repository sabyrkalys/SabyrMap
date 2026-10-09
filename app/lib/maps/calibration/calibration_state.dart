import 'affine_transform.dart';
import 'calibration_point.dart';

/// Калибровка изображения.
class CalibrationState {
  const CalibrationState({
    this.imagePath = '',
    this.points = const [],
    this.transform,
    this.opacity = 0.5,
    this.isActive = false,
  });

  /// Сколько точек можно поставить.
  static const int maxPoints = 4;

  final String imagePath;
  final List<CalibrationPoint> points;
  final AffineTransform? transform;

  /// Прозрачность изображения поверх карты, 0..1.
  final double opacity;
  final bool isActive;

  bool get isReady => points.length >= 3 && transform != null;

  CalibrationState copyWith({List<CalibrationPoint>? points, double? opacity, bool? isActive}) {
    final pts = points ?? this.points;
    return CalibrationState(
      imagePath: imagePath,
      points: List.unmodifiable(pts),
      transform: points == null ? transform : AffineTransform.fromThreePoints(pts),
      opacity: opacity ?? this.opacity,
      isActive: isActive ?? this.isActive,
    );
  }
}
