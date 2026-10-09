import 'package:app/landmarks/composite/distance/geo_math.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  test('toRadians and toDegrees', () {
    expect(GeoMath.toRadians(180), closeTo(3.14159265, 1e-8));
    expect(GeoMath.toDegrees(GeoMath.toRadians(37.5)), closeTo(37.5, 1e-12));
  });

  test('same point is 0 m', () {
    expect(Haversine.distance(loc(50, 30), loc(50, 30)), 0);
  });

  test('1° of longitude at the equator is about 111.32 km', () {
    expect(Haversine.distance(loc(0, 0), loc(0, 1)), closeTo(111320, 111320 * 0.005));
  });

  test('totalDistance, open and closed', () {
    final square = [loc(0, 0), loc(0, 1), loc(1, 1), loc(1, 0)];
    final side = Haversine.distance(loc(0, 0), loc(0, 1));
    final open = Haversine.totalDistance(square);
    final closed = Haversine.totalDistance(square, close: true);
    expect(closed - open, closeTo(Haversine.distance(loc(1, 0), loc(0, 0)), 1e-6));
    expect(open, closeTo(3 * side, side * 0.01));
    expect(Haversine.totalDistance(const []), 0);
    expect(Haversine.totalDistance([loc(0, 0)], close: true), 0);
    expect(Haversine.segmentDistance(square), open);
  });

  test('bearing N/E/S/W', () {
    expect(Bearing.fromTo(loc(0, 0), loc(1, 0)), closeTo(0, 1e-9));
    expect(Bearing.fromTo(loc(0, 0), loc(0, 1)), closeTo(90, 1e-9));
    expect(Bearing.fromTo(loc(1, 0), loc(0, 0)), closeTo(180, 1e-9));
    expect(Bearing.fromTo(loc(0, 1), loc(0, 0)), closeTo(270, 1e-9));
    final b = Bearing.fromTo(loc(50, 30), loc(49, 29));
    expect(b, inInclusiveRange(0, 360));
    expect(b, lessThan(360));
  });

  test('reverse bearing', () {
    expect(Bearing.reverse(0), 180);
    expect(Bearing.reverse(90), 270);
    expect(Bearing.reverse(270), 90);
    expect(Bearing.reverse(180), 0);
  });
}
