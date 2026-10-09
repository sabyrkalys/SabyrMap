import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/landmarks/models/landmark_location.dart';

/// Точка профиля высот.
class ElevationPoint {
  const ElevationPoint({required this.distanceMeters, required this.elevationMeters});

  /// Расстояние от начала пути, метры.
  final double distanceMeters;
  final double elevationMeters;

  @override
  bool operator ==(Object other) =>
      other is ElevationPoint && other.distanceMeters == distanceMeters && other.elevationMeters == elevationMeters;

  @override
  int get hashCode => Object.hash(distanceMeters, elevationMeters);
}

/// Профиль высот пути.
class ElevationProfile {
  const ElevationProfile({this.points = const [], this.min, this.max, this.gain = 0, this.loss = 0});

  final List<ElevationPoint> points;

  /// Наименьшая и наибольшая высота; null — высот нет.
  final double? min;
  final double? max;

  /// Набор и сброс высоты после подавления шума, метры (неотрицательные).
  final double gain;
  final double loss;

  bool get isEmpty => points.isEmpty;
}

/// Строит [ElevationProfile] по точкам пути.
abstract final class ElevationProfileBuilder {
  /// Высота точки в метрах, если есть.
  static double? elevationOf(LandmarkLocation location) => switch (location.valueOf(LocationValueType.elevation)?.value) {
    final int raw => raw / 1000,
    _ => null,
  };

  /// Точки без высоты пропускаются (но расстояние через них считается).
  /// Шум: изменение высоты учитывается, только когда оно от последней
  /// учтённой высоты достигает [noiseThresholdMeters].
  static ElevationProfile build(List<LandmarkLocation> locations, {double noiseThresholdMeters = 1.0}) {
    final points = <ElevationPoint>[];
    var distance = 0.0;
    double? minE;
    double? maxE;
    double? reference;
    var gain = 0.0;
    var loss = 0.0;
    for (final (i, location) in locations.indexed) {
      if (i > 0) distance += Haversine.distance(locations[i - 1], location);
      final e = elevationOf(location);
      if (e == null) continue;
      points.add(ElevationPoint(distanceMeters: distance, elevationMeters: e));
      minE = minE == null || e < minE ? e : minE;
      maxE = maxE == null || e > maxE ? e : maxE;
      final ref = reference;
      if (ref == null) {
        reference = e;
      } else if ((e - ref).abs() >= noiseThresholdMeters) {
        if (e > ref) {
          gain += e - ref;
        } else {
          loss += ref - e;
        }
        reference = e;
      }
    }
    return ElevationProfile(points: points, min: minE, max: maxE, gain: gain, loss: loss);
  }
}
