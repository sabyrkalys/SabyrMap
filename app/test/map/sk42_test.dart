import 'package:app/map/sk42.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Reference values from pyproj: EPSG:4326 -> +proj=tmerc +ellps=krass
  // +towgs84=23.57,-140.95,-79.8,0,0.35,0.79,-0.22, lon_0 = 6*zone-3,
  // x_0 = zone*1e6 + 500000, k = 1.
  const cases = [
    (47.99580, 37.81465, 7, 5318741.37, 7411649.30),
    (55.75222, 37.61556, 7, 6181944.70, 7413188.36),
    (43.0, 41.99, 7, 4767159.99, 7743926.61),
    (43.0, 42.01, 8, 4767152.30, 8256288.48),
    (59.93863, 30.31413, 6, 6650395.74, 6350001.93),
    (51.1694, 71.4491, 12, 5673838.22, 12671347.45),
  ];

  for (final (lat, lng, zone, x, y) in cases) {
    test('($lat, $lng) matches pyproj within 1 m', () {
      final p = toSk42(lat, lng);
      expect(p.zone, zone);
      expect(p.x, closeTo(x, 1));
      expect(p.y, closeTo(y, 1));
    });
  }

  test('a longitude exactly on a zone boundary belongs to the eastern zone', () {
    expect(toSk42(43.0, 42.0).zone, 8);
    expect(toSk42(43.0, 42.0).y, greaterThan(8000000));
  });

  // pyproj Proj(tmerc krass, lon_0 = 6*zone-3).get_factors(lon, lat).meridian_convergence
  const convergence = [
    (47.9958, 37.81465, -0.88089),
    (55.75, 37.62, -1.14076),
    (43.0, 41.99, 2.04018),
    (59.94, 30.31, -2.32863),
  ];
  for (final (lat, lng, gamma) in convergence) {
    test('convergence ($lat, $lng) matches pyproj', () {
      expect(sk42Convergence(lat, lng), closeTo(gamma, 0.01));
    });
  }

  test('convergence is zero on the central meridian', () {
    expect(sk42Convergence(50, 39), closeTo(0, 1e-9));
  });
}
