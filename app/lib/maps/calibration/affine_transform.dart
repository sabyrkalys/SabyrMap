import 'calibration_point.dart';

/// Аффинное преобразование пикселей изображения в координаты:
/// lon = a·x + b·y + c, lat = d·x + e·y + f.
class AffineTransform {
  const AffineTransform({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.e,
    required this.f,
  });

  static const AffineTransform identity = AffineTransform(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0);

  final double a, b, c, d, e, f;

  /// (lon, lat) для пикселя.
  (double x, double y) apply(double imageX, double imageY) => (a * imageX + b * imageY + c, d * imageX + e * imageY + f);

  /// Обратное преобразование; вырожденное — null.
  AffineTransform? inverse() {
    final det = a * e - b * d;
    if (det.abs() < 1e-15) return null;
    return AffineTransform(
      a: e / det,
      b: -b / det,
      c: (b * f - e * c) / det,
      d: -d / det,
      e: a / det,
      f: (d * c - a * f) / det,
    );
  }

  /// Преобразование по точкам: меньше 3 или точки на одной прямой — null.
  ///
  /// Decision: при 4 точках решается методом наименьших квадратов (при 3
  /// это точное решение) — лишняя точка уточняет, а не отбрасывается.
  static AffineTransform? fromThreePoints(List<CalibrationPoint> points) {
    if (points.length < 3) return null;
    // Нормальные уравнения: (AᵀA)·p = Aᵀv, строки A = [x, y, 1].
    final m = List.generate(3, (_) => List<double>.filled(3, 0));
    final vLon = List<double>.filled(3, 0);
    final vLat = List<double>.filled(3, 0);
    for (final pt in points) {
      final row = [pt.imageX, pt.imageY, 1.0];
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          m[i][j] += row[i] * row[j];
        }
        vLon[i] += row[i] * pt.worldLon;
        vLat[i] += row[i] * pt.worldLat;
      }
    }
    final lon = _solve3(m, vLon);
    final lat = _solve3(m, vLat);
    if (lon == null || lat == null) return null;
    return AffineTransform(a: lon[0], b: lon[1], c: lon[2], d: lat[0], e: lat[1], f: lat[2]);
  }

  /// Метод Крамера; вырожденная система — null.
  static List<double>? _solve3(List<List<double>> m, List<double> v) {
    double det(List<List<double>> x) =>
        x[0][0] * (x[1][1] * x[2][2] - x[1][2] * x[2][1]) -
        x[0][1] * (x[1][0] * x[2][2] - x[1][2] * x[2][0]) +
        x[0][2] * (x[1][0] * x[2][1] - x[1][1] * x[2][0]);
    final d = det(m);
    final scale = m.expand((r) => r).fold(0.0, (s, x) => s + x.abs());
    if (d.abs() <= 1e-12 * scale * scale * scale) return null;
    return [
      for (var col = 0; col < 3; col++)
        det([
              for (var r = 0; r < 3; r++) [for (var c = 0; c < 3; c++) c == col ? v[r] : m[r][c]],
            ]) /
            d,
    ];
  }

  Map<String, Object?> toJson() => {'a': a, 'b': b, 'c': c, 'd': d, 'e': e, 'f': f};

  @override
  bool operator ==(Object other) =>
      other is AffineTransform &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.e == e &&
      other.f == f;

  @override
  int get hashCode => Object.hash(a, b, c, d, e, f);
}
