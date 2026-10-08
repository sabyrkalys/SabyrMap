import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../map/sk42.dart';

/// How coordinates are written in the «Координаты» dialog.
enum CoordsSystem {
  /// Latitude and longitude in degrees, as «47.993239°N 37.801170°E».
  wgs84('Широта/Долгота (Град.)'),

  /// СК-42 Gauss–Krüger X (northing) and Y (zone + easting), metres.
  sk42('СК-42 (GAUSS-KRUGER ZONES)');

  const CoordsSystem(this.label);

  final String label;

  /// «X = 5318818  Y = 7411502», or «47.993239°N  37.801170°E».
  String describe(LatLng point) => switch (this) {
    CoordsSystem.wgs84 => '${formatLatitude(point.latitude)}  ${formatLongitude(point.longitude)}',
    CoordsSystem.sk42 => () {
      final p = toSk42(point.latitude, point.longitude);
      return 'X = ${p.x.round()}  Y = ${p.y.round()}';
    }(),
  };
}

/// Degrees without a sign, to six places: «47.993239».
String formatDegrees(double degrees) => degrees.abs().toStringAsFixed(6);

/// «47.993239°N», «12.500000°S».
String formatLatitude(double lat) => '${formatDegrees(lat)}°${lat < 0 ? 'S' : 'N'}';

/// «37.801170°E», «70.250000°W».
String formatLongitude(double lng) => '${formatDegrees(lng)}°${lng < 0 ? 'W' : 'E'}';

/// What «ОК» in the «Координаты» dialog returns.
class CoordinatesResult {
  const CoordinatesResult({required this.system, required this.x, required this.y});

  final CoordsSystem system;

  /// Latitude, or СК-42 X.
  final double x;

  /// Longitude, or СК-42 Y.
  final double y;

  /// The point on the map (WGS84).
  LatLng get point => switch (system) {
    CoordsSystem.wgs84 => LatLng(x, y),
    CoordsSystem.sk42 => () {
      final (lat, lng) = fromSk42(x, y);
      return LatLng(lat, lng);
    }(),
  };

  /// Whether x and y are a place on Earth in [system]: latitude ±90 and
  /// longitude ±180, or a СК-42 X up to 10 000 km and a Y with a zone 1–60.
  bool get isValid => switch (system) {
    CoordsSystem.wgs84 => x.abs() <= 90 && y.abs() <= 180,
    CoordsSystem.sk42 => x > 0 && x < 10000000 && y >= 1000000 && y < 61000000,
  };
}

/// The first two numbers in [text] («X=5318818 Y=7411502», «48,1 37,8»):
/// a comma may stand for the decimal point. Null when there are fewer.
(double, double)? parseCoordinatePair(String text) {
  final numbers = RegExp(
    r'-?\d+(?:[.,]\d+)?',
  ).allMatches(text).map((m) => double.tryParse(m.group(0)!.replaceAll(',', '.'))).whereType<double>().toList();
  if (numbers.length < 2) return null;
  return (numbers[0], numbers[1]);
}

/// Latitude and longitude from text like «47.993239°N 37.801170°E»,
/// «47,99 S 37,8 W» or «-47.99 37.8»: the first two numbers, each turned
/// negative by a following S/W (Ю/З). Null when there are fewer.
(double, double)? parseLatLngPair(String text) {
  final values = RegExp(r'(-?\d+(?:[.,]\d+)?)\s*°?\s*([NSEWnsewСЮВЗсювз])?')
      .allMatches(text)
      .map((m) {
        final value = double.tryParse(m.group(1)!.replaceAll(',', '.'));
        if (value == null) return null;
        final south = 'SsWwЮюЗз'.contains(m.group(2) ?? '-');
        return south ? -value.abs() : value;
      })
      .whereType<double>()
      .toList();
  if (values.length < 2) return null;
  return (values[0], values[1]);
}
