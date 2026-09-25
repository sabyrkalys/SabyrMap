import 'dart:math' as math;

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// Sunrise and sunset (UTC) around the point's solar noon on the date of
/// [date], by the NOAA solar calculator (zenith 90.833°); for points far
/// from Greenwich the results can fall on the neighbouring UTC day. Null
/// when the sun stays above or below the horizon — including, rarely, a
/// grazing event right at the start or end of polar day/night.
({DateTime? sunrise, DateTime? sunset}) sunTimes(double lat, double lng, DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  return (sunrise: _event(lat, lng, day, rise: true), sunset: _event(lat, lng, day, rise: false));
}

DateTime? _event(double lat, double lng, DateTime day, {required bool rise}) {
  // Julian day at 0h UTC.
  final julianDay = day.millisecondsSinceEpoch / 86400000 + 2440587.5;
  var minutes = 720 - 4 * lng;
  for (var i = 0; i < 3; i++) {
    final jc = (julianDay - 2451545 + minutes / 1440) / 36525;
    final l0 = (280.46646 + jc * (36000.76983 + jc * 0.0003032)) % 360;
    final m = 357.52911 + jc * (35999.05029 - 0.0001537 * jc);
    final e = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc);
    final c = math.sin(_rad(m)) * (1.914602 - jc * (0.004817 + 0.000014 * jc)) +
        math.sin(_rad(2 * m)) * (0.019993 - 0.000101 * jc) +
        math.sin(_rad(3 * m)) * 0.000289;
    final omega = 125.04 - 1934.136 * jc;
    final apparentLong = l0 + c - 0.00569 - 0.00478 * math.sin(_rad(omega));
    final meanObliquity = 23 + (26 + (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60) / 60;
    final obliquity = meanObliquity + 0.00256 * math.cos(_rad(omega));
    final declination = _deg(math.asin(math.sin(_rad(obliquity)) * math.sin(_rad(apparentLong))));
    final yy = math.pow(math.tan(_rad(obliquity / 2)), 2).toDouble();
    final equationOfTime = 4 *
        _deg(yy * math.sin(2 * _rad(l0)) -
            2 * e * math.sin(_rad(m)) +
            4 * e * yy * math.sin(_rad(m)) * math.cos(2 * _rad(l0)) -
            0.5 * yy * yy * math.sin(4 * _rad(l0)) -
            1.25 * e * e * math.sin(2 * _rad(m)));
    final cosH = math.cos(_rad(90.833)) / (math.cos(_rad(lat)) * math.cos(_rad(declination))) -
        math.tan(_rad(lat)) * math.tan(_rad(declination));
    if (cosH > 1 || cosH < -1) return null;
    final hourAngle = _deg(math.acos(cosH));
    final solarNoon = 720 - 4 * lng - equationOfTime;
    minutes = rise ? solarNoon - 4 * hourAngle : solarNoon + 4 * hourAngle;
  }
  return day.add(Duration(microseconds: (minutes * 60e6).round()));
}
