import 'package:app/geo/wmm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // NOAA WMM2025_TEST_VALUES.txt: (year, height km, lat, lon, declination).
  const cases = [
    (2025.0, 0.0, 80.0, 0.0, 1.28),
    (2025.0, 0.0, 0.0, 120.0, -0.16),
    (2025.0, 0.0, -80.0, 240.0, 68.78),
    (2025.0, 100.0, 80.0, 0.0, 0.85),
    (2025.0, 100.0, 0.0, 120.0, -0.15),
    (2025.0, 100.0, -80.0, 240.0, 68.21),
    (2027.5, 0.0, 80.0, 0.0, 2.59),
    (2027.5, 0.0, 0.0, 120.0, -0.24),
    (2027.5, 0.0, -80.0, 240.0, 68.49),
    (2027.5, 100.0, 80.0, 0.0, 2.16),
    (2027.5, 100.0, 0.0, 120.0, -0.23),
    (2027.5, 100.0, -80.0, 240.0, 67.93),
  ];
  for (final (year, h, lat, lon, d) in cases) {
    test('declination $year h=$h ($lat, $lon) matches NOAA', () {
      expect(magneticDeclination(lat, lon, decimalYear: year, altitudeKm: h), closeTo(d, 0.02));
    });
  }

  test('decimalYear', () {
    expect(decimalYear(DateTime.utc(2025)), 2025.0);
    expect(decimalYear(DateTime.utc(2027, 7, 2, 12)), closeTo(2027.5, 0.002));
  });
}
