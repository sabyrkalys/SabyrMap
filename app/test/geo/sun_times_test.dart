import 'package:app/geo/sun_times.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // References from Python `astral` (UTC), within 1.5 min.
  const cases = [
    (47.9958, 37.81465, 2026, 9, 25, '03:19:31', '15:20:32'),
    (55.75, 37.62, 2026, 6, 21, '00:45:00', '18:17:37'),
    (55.75, 37.62, 2026, 12, 21, '05:57:49', '12:57:14'),
    (0.0, 0.0, 2026, 1, 1, '06:00:01', '18:07:06'),
  ];

  DateTime at(int y, int m, int d, String hms) {
    final p = hms.split(':').map(int.parse).toList();
    return DateTime.utc(y, m, d, p[0], p[1], p[2]);
  }

  for (final (lat, lng, y, m, d, rise, set) in cases) {
    test('($lat, $lng) $y-$m-$d', () {
      final t = sunTimes(lat, lng, DateTime(y, m, d));
      expect(t.sunrise!.difference(at(y, m, d, rise)).inSeconds.abs(), lessThan(90));
      expect(t.sunset!.difference(at(y, m, d, set)).inSeconds.abs(), lessThan(90));
      expect(t.sunrise!.isUtc, isTrue);
    });
  }

  test('polar day and polar night give no times', () {
    final summer = sunTimes(78.2, 15.6, DateTime(2026, 6, 21));
    expect(summer.sunrise, isNull);
    expect(summer.sunset, isNull);
    final winter = sunTimes(78.2, 15.6, DateTime(2026, 12, 21));
    expect(winter.sunrise, isNull);
    expect(winter.sunset, isNull);
  });
}
