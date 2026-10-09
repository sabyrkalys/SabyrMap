import 'package:app/landmarks/composite/distance/geo_math.dart';
import 'package:app/landmarks/models/landmark_location.dart';

import 'measure_color_scheme.dart';
import 'measure_segment.dart';

/// Отрезки и длина измерения.
abstract final class MeasureCalculator {
  static List<MeasureSegment> buildSegments(List<LandmarkLocation> points) => [
    for (var i = 1; i < points.length; i++)
      () {
        final azimuth = Bearing.fromTo(points[i - 1], points[i]);
        return MeasureSegment(
          from: points[i - 1],
          to: points[i],
          distanceMeters: Haversine.distance(points[i - 1], points[i]),
          azimuthDeg: azimuth,
          segmentColor: MeasureColorScheme.colorFor(azimuth),
        );
      }(),
  ];

  static double totalDistance(List<LandmarkLocation> points) => Haversine.totalDistance(points);
}
