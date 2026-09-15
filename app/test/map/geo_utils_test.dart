import 'package:app/map/geo_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('distanceMeters is zero for identical points', () {
    expect(distanceMeters(43.0, 74.0, 43.0, 74.0), 0);
  });

  test('distanceMeters returns a plausible distance for one degree of latitude', () {
    // Roughly 111 km per degree of latitude.
    final distance = distanceMeters(0, 0, 1, 0);
    expect(distance, greaterThan(110000));
    expect(distance, lessThan(112000));
  });

  test('bearingDegrees points north (0) for due-north targets', () {
    final bearing = bearingDegrees(0, 0, 1, 0);
    expect(bearing, closeTo(0, 0.01));
  });

  test('bearingDegrees points east (90) for due-east targets', () {
    final bearing = bearingDegrees(0, 0, 0, 1);
    expect(bearing, closeTo(90, 0.01));
  });
}
