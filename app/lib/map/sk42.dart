import 'dart:math' as math;

/// Gauss–Krüger rectangular coordinates on the СК-42 (Pulkovo 1942) datum.
/// [x] is the northing; [y] carries the zone number in front of the
/// easting (zone·10⁶ + 500 000 + easting), both in metres.
class Sk42Point {
  const Sk42Point({required this.x, required this.y, required this.zone});

  final double x;
  final double y;
  final int zone;
}

const double _wgsA = 6378137.0;
const double _wgsF = 1 / 298.257223563;
const double _krassA = 6378245.0;
const double _krassF = 1 / 298.3;

// СК-42 -> WGS84 Helmert, position-vector convention (ГОСТ Р 51794-2008,
// the same set as PROJ's +towgs84=23.57,-140.95,-79.8,0,0.35,0.79,-0.22).
// toSk42 applies it in reverse.
const double _tx = 23.57;
const double _ty = -140.95;
const double _tz = -79.8;
const double _rxSeconds = 0;
const double _rySeconds = 0.35;
const double _rzSeconds = 0.79;
const double _scalePpm = -0.22;

double _rad(double degrees) => degrees * math.pi / 180;
double _deg(double radians) => radians * 180 / math.pi;
double _secondsToRad(double seconds) => _rad(seconds / 3600);

(double, double, double) _toGeocentric(double lat, double lng, double a, double f) {
  final e2 = f * (2 - f);
  final phi = _rad(lat);
  final lambda = _rad(lng);
  final n = a / math.sqrt(1 - e2 * math.sin(phi) * math.sin(phi));
  return (
    n * math.cos(phi) * math.cos(lambda),
    n * math.cos(phi) * math.sin(lambda),
    n * (1 - e2) * math.sin(phi),
  );
}

(double, double) _toGeodetic(double x, double y, double z, double a, double f) {
  final e2 = f * (2 - f);
  final lambda = math.atan2(y, x);
  final p = math.sqrt(x * x + y * y);
  var phi = math.atan2(z, p * (1 - e2));
  for (var i = 0; i < 10; i++) {
    final n = a / math.sqrt(1 - e2 * math.sin(phi) * math.sin(phi));
    final h = p / math.cos(phi) - n;
    phi = math.atan2(z, p * (1 - e2 * n / (n + h)));
  }
  return (_deg(phi), _deg(lambda));
}

/// WGS84 latitude/longitude (degrees) to СК-42 Gauss–Krüger, 6° zones.
/// The zone is taken from the WGS84 longitude; a longitude exactly on a
/// boundary belongs to the eastern zone.
Sk42Point toSk42(double lat, double lng) {
  final (xw, yw, zw) = _toGeocentric(lat, lng, _wgsA, _wgsF);
  final rx = _secondsToRad(_rxSeconds);
  final ry = _secondsToRad(_rySeconds);
  final rz = _secondsToRad(_rzSeconds);
  final s = 1 + _scalePpm * 1e-6;
  final dx = (xw - _tx) / s;
  final dy = (yw - _ty) / s;
  final dz = (zw - _tz) / s;
  // Inverse of the small-angle rotation matrix is its transpose.
  final xk = dx + rz * dy - ry * dz;
  final yk = -rz * dx + dy + rx * dz;
  final zk = ry * dx - rx * dy + dz;
  final (latK, lngK) = _toGeodetic(xk, yk, zk, _krassA, _krassF);

  final zone = (lng / 6).floor() + 1;
  final centralMeridian = zone * 6 - 3;

  const a = _krassA;
  const e2 = _krassF * (2 - _krassF);
  const ep2 = e2 / (1 - e2);
  const e4 = e2 * e2;
  const e6 = e4 * e2;
  final phi = _rad(latK);
  final sinPhi = math.sin(phi);
  final cosPhi = math.cos(phi);
  final n = a / math.sqrt(1 - e2 * sinPhi * sinPhi);
  final t = math.tan(phi) * math.tan(phi);
  final c = ep2 * cosPhi * cosPhi;
  final aa = _rad(lngK - centralMeridian) * cosPhi;
  final m = a *
      ((1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * phi -
          (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * math.sin(2 * phi) +
          (15 * e4 / 256 + 45 * e6 / 1024) * math.sin(4 * phi) -
          (35 * e6 / 3072) * math.sin(6 * phi));
  final easting = n *
      (aa +
          (1 - t + c) * math.pow(aa, 3) / 6 +
          (5 - 18 * t + t * t + 72 * c - 58 * ep2) * math.pow(aa, 5) / 120);
  final northing = m +
      n *
          math.tan(phi) *
          (aa * aa / 2 +
              (5 - t + 9 * c + 4 * c * c) * math.pow(aa, 4) / 24 +
              (61 - 58 * t + t * t + 600 * c - 330 * ep2) * math.pow(aa, 6) / 720);
  return Sk42Point(x: northing, y: zone * 1000000 + 500000 + easting, zone: zone);
}
/// Meridian convergence (degrees): the angle from true north to grid north
/// (the X axis) in the point's 6° Gauss–Krüger zone on the Krasovsky
/// ellipsoid; positive east of the zone's central meridian.
double sk42Convergence(double lat, double lng) {
  final zone = (lng / 6).floor() + 1;
  final dl = _rad(lng - (zone * 6 - 3));
  final phi = _rad(lat);
  const e2 = _krassF * (2 - _krassF);
  const ep2 = e2 / (1 - e2);
  final cosPhi = math.cos(phi);
  final eta2 = ep2 * cosPhi * cosPhi;
  final t2 = math.tan(phi) * math.tan(phi);
  final l2 = math.pow(dl * cosPhi, 2).toDouble();
  final gamma = dl *
      math.sin(phi) *
      (1 + l2 / 3 * (1 + 3 * eta2 + 2 * eta2 * eta2) + l2 * l2 / 15 * (2 - t2));
  return _deg(gamma);
}
