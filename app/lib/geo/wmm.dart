import 'dart:math' as math;

import 'wmm_coefficients.dart';

const int _maxDegree = 12;
const double _wgsA = 6378.137; // km
const double _wgsF = 1 / 298.257223563;
const double _referenceRadius = 6371.2; // km

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// Year with fraction, e.g. 2027.5 for early July 2027 (UTC).
double decimalYear(DateTime utc) {
  final start = DateTime.utc(utc.year);
  final end = DateTime.utc(utc.year + 1);
  return utc.year + utc.difference(start).inMicroseconds / end.difference(start).inMicroseconds;
}

final Map<(int, int), (double, double, double, double)> _coefficients = {
  for (final (n, m, g, h, gd, hd) in wmmCoefficients) (n, m): (g, h, gd, hd),
};

/// Magnetic declination (degrees, east positive) from the World Magnetic
/// Model WMM2025 at a WGS84 point.
double magneticDeclination(double lat, double lng, {required double decimalYear, double altitudeKm = 0}) {
  const e2 = _wgsF * (2 - _wgsF);
  final phi = _rad(lat);
  final lambda = _rad(lng);
  final rc = _wgsA / math.sqrt(1 - e2 * math.sin(phi) * math.sin(phi));
  final p = (rc + altitudeKm) * math.cos(phi);
  final z = (rc * (1 - e2) + altitudeKm) * math.sin(phi);
  final r = math.sqrt(p * p + z * z);
  final phiC = math.asin(z / r);
  final dt = decimalYear - wmmEpoch;

  final x = math.sin(phiC);
  final y = math.cos(phiC);
  final pnm = List.generate(_maxDegree + 1, (_) => List.filled(_maxDegree + 1, 0.0));
  final dpnm = List.generate(_maxDegree + 1, (_) => List.filled(_maxDegree + 1, 0.0));
  pnm[0][0] = 1;
  for (var n = 1; n <= _maxDegree; n++) {
    for (var m = 0; m <= n; m++) {
      if (n == m) {
        final k = n > 1 ? math.sqrt(1 - 1 / (2 * n)) : 1.0;
        pnm[n][m] = k * y * pnm[n - 1][m - 1];
        dpnm[n][m] = k * (y * dpnm[n - 1][m - 1] + x * pnm[n - 1][m - 1]);
      } else if (n == 1 && m == 0) {
        pnm[1][0] = x;
        dpnm[1][0] = -y;
      } else {
        final k1 = (2 * n - 1) / math.sqrt((n * n - m * m).toDouble());
        final k2 = n > 1 ? math.sqrt(((n - 1) * (n - 1) - m * m) / (n * n - m * m)) : 0.0;
        final prev2 = n >= 2 ? pnm[n - 2][m] : 0.0;
        final dprev2 = n >= 2 ? dpnm[n - 2][m] : 0.0;
        pnm[n][m] = k1 * x * pnm[n - 1][m] - k2 * prev2;
        dpnm[n][m] = k1 * (x * dpnm[n - 1][m] - y * pnm[n - 1][m]) - k2 * dprev2;
      }
    }
  }

  var bx = 0.0;
  var by = 0.0;
  var bz = 0.0;
  for (var n = 1; n <= _maxDegree; n++) {
    final rr = math.pow(_referenceRadius / r, n + 2).toDouble();
    for (var m = 0; m <= n; m++) {
      final (g0, h0, gd, hd) = _coefficients[(n, m)]!;
      final g = g0 + dt * gd;
      final h = h0 + dt * hd;
      final cm = math.cos(m * lambda);
      final sm = math.sin(m * lambda);
      final t = g * cm + h * sm;
      bx += rr * t * dpnm[n][m];
      if (y > 1e-12) by += rr * m * (g * sm - h * cm) * pnm[n][m] / y;
      bz += -(n + 1) * rr * t * pnm[n][m];
    }
  }
  final psi = phiC - phi;
  final north = bx * math.cos(psi) - bz * math.sin(psi);
  return _deg(math.atan2(by, north));
}
