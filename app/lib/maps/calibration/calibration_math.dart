import 'dart:math';

import 'package:app/maps/file_maps/map_bounds.dart';

import 'affine_transform.dart';
import 'calibration_point.dart';

/// Расчёты калибровки изображения.
abstract final class CalibrationMath {
  /// Преобразование по точкам ([AffineTransform.fromThreePoints]).
  static AffineTransform? transformFor(List<CalibrationPoint> points) => AffineTransform.fromThreePoints(points);

  /// Пиксель изображения для координат; вырожденное преобразование — null.
  static (double imageX, double imageY)? worldToImage(AffineTransform t, double lon, double lat) =>
      t.inverse()?.apply(lon, lat);

  /// Наибольшее расхождение точек с преобразованием, градусы.
  static double maxResidualDegrees(AffineTransform t, List<CalibrationPoint> points) {
    var worst = 0.0;
    for (final pt in points) {
      final (lon, lat) = t.apply(pt.imageX, pt.imageY);
      worst = max(worst, sqrt(pow(lon - pt.worldLon, 2) + pow(lat - pt.worldLat, 2)));
    }
    return worst;
  }

  /// Границы изображения [width]×[height] после преобразования.
  static MapBounds boundsOf(AffineTransform t, double width, double height) {
    final corners = [t.apply(0, 0), t.apply(width, 0), t.apply(0, height), t.apply(width, height)];
    return MapBounds(
      northLat: corners.map((c) => c.$2).reduce(max),
      southLat: corners.map((c) => c.$2).reduce(min),
      westLon: corners.map((c) => c.$1).reduce(min),
      eastLon: corners.map((c) => c.$1).reduce(max),
    );
  }
}
