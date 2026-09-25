# Point Info (i) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The «i» icon in the crosshair card opens an ИНФОРМАЦИЯ bottom sheet for the point under the crosshair: coordinates, magnetic declination (WMM2025), meridian convergence (СК-42 zone), sunrise/sunset, phone time zone.

**Architecture:** Pure computations in `lib/geo/wmm.dart`, `lib/geo/sun_times.dart` and `sk42Convergence` in `lib/map/sk42.dart`, each tested against external references (NOAA test values, `astral`, `pyproj`). Formatting helpers and the sheet in `lib/map/point_info_sheet.dart`. The crosshair card's info button becomes active; `MapScreen` opens the sheet.

**Tech Stack:** Flutter 3.35.5, flutter_riverpod 3.x, maplibre_gl 0.26.2. Reference tools (already on the laptop): Python with `pyproj` 3.7.2 and `astral`.

**Spec:** `docs/superpowers/specs/2026-09-25-point-info-design.md`

## Global Constraints

- Sheet title `ИНФОРМАЦИЯ`; row labels exactly: «Координаты», «Склонение (магнитное)», «Конвергенция меридианов», «Время восхода и заката», «Часовой пояс».
- Angles: one decimal + `°` + space + `В` (east, > 0) or `З` (west, < 0); a value that rounds to 0.0 shows `0.0°`.
- Times `HH:MM` 24 h in the phone's time zone; no event → `—`. Time zone `UTC+3`, `UTC+5:30`, `UTC−3:30` (U+2212 minus), `UTC+0`.
- Coordinates: same as the info panel line 1 (СК-42 `X = … Y = …` when `MenuToggle.settingsSk42Grid` is on, else `47.99580, 37.81465`).
- WMM2025 coefficients from NOAA `WMM.COF` (epoch 2025.0), sea level, decimal year of today.
- Sun: NOAA algorithm, zenith 90.833°.
- Convergence: Gauss–Krüger on Krasovsky, zone from WGS84 longitude as in `toSk42`, positive east of the central meridian.
- Icons `sunrise.svg` / `sunset.svg` from MDI `weather-sunset-up` / `weather-sunset-down` (Apache-2.0), normalised to `width="24" height="24" viewBox="0 0 24 24" fill="currentColor"`.
- Run Flutter from `app/`, `--timeout 60s`. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Polar day / polar night must give `—`, never an exception or a wrong time: Task 2 tests at 78.2° N in June and December.
2. Declination near a magnetic pole (lat ±80) stays finite: Task 1 test values include ±80°.
3. Convergence exactly on a central meridian is `0.0°` without a letter: Task 4 formatting test.
4. Negative UTC offsets and half-hour offsets format correctly: Task 4 test.
5. Opening the sheet before the map has settled shows «Карта ещё не готова», not a crash: Task 5 test.

---

### Task 1: WMM2025 declination

**Files:** Create `app/lib/geo/wmm_coefficients.dart` (generated), `app/lib/geo/wmm.dart`; Test `app/test/geo/wmm_test.dart`.

**Interfaces — Produces:** `double magneticDeclination(double lat, double lng, {required double decimalYear, double altitudeKm = 0})` (degrees, east positive); `double decimalYear(DateTime utc)`.

- [ ] **Step 1: Generate the coefficient table.** From the scratchpad copy of NOAA's `WMM.COF` (downloaded from `https://www.ncei.noaa.gov/sites/default/files/2024-12/WMM2025COF.zip`), run:

```bash
python - <<'PY'
rows=[]
for ln in open(r'C:/Temp/claude/C--Users--------------------------------alpinequest-saas/c009b5b8-fd6c-45d6-8a89-08ebe10f846d/scratchpad/wmm/WMM2025COF/WMM.COF').read().splitlines()[1:]:
    p=ln.split()
    if len(p)<6 or p[0].startswith('9999'): continue
    rows.append(f"  ({p[0]}, {p[1]}, {p[2]}, {p[3]}, {p[4]}, {p[5]}),")
open('app/lib/geo/wmm_coefficients.dart','w',encoding='utf-8').write(
"// WMM2025 Gauss coefficients from NOAA/NCEI WMM.COF (public domain).\n"
"// (n, m, g, h, g-dot, h-dot) in nT and nT/year; epoch 2025.0.\n"
"const double wmmEpoch = 2025.0;\n\n"
"const List<(int, int, double, double, double, double)> wmmCoefficients = [\n" + "\n".join(rows) + "\n];\n")
print(len(rows))
PY
```

Expected: `90`.

- [ ] **Step 2: Failing test** `app/test/geo/wmm_test.dart`:

```dart
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
```

- [ ] **Step 3:** `flutter test test/geo/wmm_test.dart --timeout 60s` → compile error.

- [ ] **Step 4: Implement** `app/lib/geo/wmm.dart` (port of the prototype verified against all NOAA values to < 0.005°):

```dart
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
```

- [ ] **Step 5:** same test command → 13 pass. **Step 6:** commit `feat(app): WMM2025 magnetic declination`.

---

### Task 2: Sunrise and sunset

**Files:** Create `app/lib/geo/sun_times.dart`; Test `app/test/geo/sun_times_test.dart`.

**Interfaces — Produces:** `({DateTime? sunrise, DateTime? sunset}) sunTimes(double lat, double lng, DateTime date)` — `date`'s year/month/day taken as the calendar day; results in UTC; null when the sun doesn't cross the horizon.

- [ ] **Step 1: Failing test**

```dart
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
```

- [ ] **Step 2:** `flutter test test/geo/sun_times_test.dart --timeout 60s` → compile error.

- [ ] **Step 3: Implement** `app/lib/geo/sun_times.dart`:

```dart
import 'dart:math' as math;

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// Sunrise and sunset (UTC) for the calendar day of [date] at a point, by
/// the NOAA solar calculator (zenith 90.833°). Null when the sun stays
/// above or below the horizon all day.
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
```

- [ ] **Step 4:** test → 5 pass. **Step 5:** commit `feat(app): sunrise and sunset (NOAA)`.

---

### Task 3: СК-42 meridian convergence

**Files:** Modify `app/lib/map/sk42.dart`; Test `app/test/map/sk42_test.dart` (append).

**Interfaces — Produces:** `double sk42Convergence(double lat, double lng)` (degrees, positive east of the zone's central meridian).

- [ ] **Step 1: Failing test** — append to `sk42_test.dart` inside `main`:

```dart
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
```

- [ ] **Step 2:** run `flutter test test/map/sk42_test.dart --timeout 60s` → compile error.

- [ ] **Step 3: Implement** — append to `sk42.dart`:

```dart
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
```

(WGS84 latitude/longitude are used directly: the datum shift changes γ by far less than 0.01°.)

- [ ] **Step 4:** test → pass. **Step 5:** commit `feat(app): СК-42 meridian convergence`.

---

### Task 4: Info sheet widget, formatting, icons

**Files:** Create `app/assets/icons/sunrise.svg`, `app/assets/icons/sunset.svg`, `app/lib/map/point_info_sheet.dart`; Modify `app/lib/app_icons.dart`; Test `app/test/map/point_info_sheet_test.dart`.

**Interfaces — Consumes:** Tasks 1–3, `toSk42`, `MenuToggle`, `MenuPanel.background`, `AppTextStyles`.
**Produces:** `String formatAngleEw(double degrees)`, `String formatUtcOffset(Duration offset)`, `String formatClock(DateTime? local)`; `PointInfoSheet({Key? key, required LatLng point, required bool sk42, required DateTime now})`; `Future<void> showPointInfoSheet(BuildContext context, {required LatLng point, required bool sk42})`.

- [ ] **Step 1: Icons.** Write `app/assets/icons/sunrise.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
  <path d="M3,12H7A5,5 0 0,1 12,7A5,5 0 0,1 17,12H21A1,1 0 0,1 22,13A1,1 0 0,1 21,14H3A1,1 0 0,1 2,13A1,1 0 0,1 3,12M15,12A3,3 0 0,0 12,9A3,3 0 0,0 9,12H15M12,2L14.39,5.42C13.65,5.15 12.84,5 12,5C11.16,5 10.35,5.15 9.61,5.42L12,2M3.34,7L7.5,6.65C6.9,7.16 6.36,7.78 5.94,8.5C5.5,9.24 5.25,10 5.11,10.79L3.34,7M20.65,7L18.88,10.79C18.74,10 18.47,9.23 18.05,8.5C17.63,7.78 17.1,7.15 16.5,6.64L20.65,7M12.71,16.3L15.82,19.41C16.21,19.8 16.21,20.43 15.82,20.82C15.43,21.21 14.8,21.21 14.41,20.82L12,18.41L9.59,20.82C9.2,21.21 8.57,21.21 8.18,20.82C7.79,20.43 7.79,19.8 8.18,19.41L11.29,16.3C11.5,16.1 11.74,16 12,16C12.26,16 12.5,16.1 12.71,16.3Z"></path>
</svg>
```

and `app/assets/icons/sunset.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
  <path d="M3,12H7A5,5 0 0,1 12,7A5,5 0 0,1 17,12H21A1,1 0 0,1 22,13A1,1 0 0,1 21,14H3A1,1 0 0,1 2,13A1,1 0 0,1 3,12M15,12A3,3 0 0,0 12,9A3,3 0 0,0 9,12H15M12,2L14.39,5.42C13.65,5.15 12.84,5 12,5C11.16,5 10.35,5.15 9.61,5.42L12,2M3.34,7L7.5,6.65C6.9,7.16 6.36,7.78 5.94,8.5C5.5,9.24 5.25,10 5.11,10.79L3.34,7M20.65,7L18.88,10.79C18.74,10 18.47,9.23 18.05,8.5C17.63,7.78 17.1,7.15 16.5,6.64L20.65,7M12.71,20.71L15.82,17.6C16.21,17.21 16.21,16.57 15.82,16.18C15.43,15.79 14.8,15.79 14.41,16.18L12,18.59L9.59,16.18C9.2,15.79 8.57,15.79 8.18,16.18C7.79,16.57 7.79,17.21 8.18,17.6L11.29,20.71C11.5,20.9 11.74,21 12,21C12.26,21 12.5,20.9 12.71,20.71Z"></path>
</svg>
```

In `app/lib/app_icons.dart` add (alphabetical with the others) `static const String sunrise = '$_base/sunrise.svg';` and `static const String sunset = '$_base/sunset.svg';`, and add both to the list of all icons if the file keeps one (check with `grep -n "static const List" app/lib/app_icons.dart`; the existing test `test/widgets/app_icon_test.dart` or similar may iterate it).

- [ ] **Step 2: Failing test** `app/test/map/point_info_sheet_test.dart`:

```dart
import 'package:app/map/point_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  test('formatAngleEw', () {
    expect(formatAngleEw(8.14), '8.1° В');
    expect(formatAngleEw(-0.62), '0.6° З');
    expect(formatAngleEw(0.02), '0.0°');
    expect(formatAngleEw(-0.04), '0.0°');
  });

  test('formatUtcOffset', () {
    expect(formatUtcOffset(const Duration(hours: 3)), 'UTC+3');
    expect(formatUtcOffset(const Duration(hours: 5, minutes: 30)), 'UTC+5:30');
    expect(formatUtcOffset(const Duration(hours: -3, minutes: -30)), 'UTC−3:30');
    expect(formatUtcOffset(Duration.zero), 'UTC+0');
  });

  test('formatClock', () {
    expect(formatClock(DateTime(2026, 9, 25, 5, 3)), '05:03');
    expect(formatClock(null), '—');
  });

  Future<void> pump(WidgetTester tester, {required bool sk42}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PointInfoSheet(point: const LatLng(47.9958, 37.81465), sk42: sk42, now: DateTime(2026, 9, 25, 12)),
        ),
      ),
    );
  }

  testWidgets('title and the five rows in order', (tester) async {
    await pump(tester, sk42: false);
    expect(find.text('ИНФОРМАЦИЯ'), findsOneWidget);
    const labels = [
      'Координаты',
      'Склонение (магнитное)',
      'Конвергенция меридианов',
      'Время восхода и заката',
      'Часовой пояс',
    ];
    for (var i = 1; i < labels.length; i++) {
      expect(
        tester.getTopLeft(find.text(labels[i])).dy,
        greaterThan(tester.getTopLeft(find.text(labels[i - 1])).dy),
        reason: labels[i],
      );
    }
    expect(find.text('47.99580, 37.81465'), findsOneWidget);
    expect(find.text('0.9° З'), findsOneWidget); // convergence −0.88°
    expect(find.byKey(const Key('point_info_sunrise_icon')), findsOneWidget);
    expect(find.byKey(const Key('point_info_sunset_icon')), findsOneWidget);
    expect(find.textContaining('UTC'), findsOneWidget);
  });

  testWidgets('coordinates follow the СК-42 setting', (tester) async {
    await pump(tester, sk42: true);
    expect(find.text('X = 5318741 Y = 7411649'), findsOneWidget);
  });

  testWidgets('declination row shows a value with a side letter', (tester) async {
    await pump(tester, sk42: false);
    final value = tester.widget<Text>(find.byKey(const Key('point_info_declination'))).data!;
    expect(value, matches(RegExp(r'^\d+\.\d° [ВЗ]$|^0\.0°$')));
  });
}
```

- [ ] **Step 3:** `flutter test test/map/point_info_sheet_test.dart --timeout 60s` → compile error.

- [ ] **Step 4: Implement** `app/lib/map/point_info_sheet.dart`:

```dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app_icons.dart';
import '../geo/sun_times.dart';
import '../geo/wmm.dart';
import '../menu/menu_widgets.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icon.dart';
import 'sk42.dart';

/// «8.1° В» / «0.6° З»; a value that rounds to zero is «0.0°».
String formatAngleEw(double degrees) {
  final text = degrees.abs().toStringAsFixed(1);
  if (text == '0.0') return '0.0°';
  return '$text° ${degrees > 0 ? 'В' : 'З'}';
}

/// «UTC+3», «UTC+5:30», «UTC−3:30», «UTC+0».
String formatUtcOffset(Duration offset) {
  final minutes = offset.inMinutes;
  final sign = minutes < 0 ? '−' : '+';
  final abs = minutes.abs();
  final hours = abs ~/ 60;
  final rest = abs % 60;
  return rest == 0 ? 'UTC$sign$hours' : 'UTC$sign$hours:${rest.toString().padLeft(2, '0')}';
}

/// «05:03» in the given (local) time; «—» when there is no event.
String formatClock(DateTime? local) {
  if (local == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

Future<void> showPointInfoSheet(BuildContext context, {required LatLng point, required bool sk42}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => PointInfoSheet(point: point, sk42: sk42, now: DateTime.now()),
  );
}

/// ИНФОРМАЦИЯ: details about one point (the spot under the crosshair).
class PointInfoSheet extends StatelessWidget {
  const PointInfoSheet({super.key, required this.point, required this.sk42, required this.now});

  final LatLng point;
  final bool sk42;

  /// Local "now" of the phone; its date picks the day for sunrise/sunset,
  /// its offset is the time zone shown.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final lat = point.latitude;
    final lng = point.longitude;
    final String coordinates;
    if (sk42) {
      final p = toSk42(lat, lng);
      coordinates = 'X = ${p.x.round()} Y = ${p.y.round()}';
    } else {
      coordinates = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
    final declination = magneticDeclination(lat, lng, decimalYear: decimalYear(now.toUtc()));
    final convergence = sk42Convergence(lat, lng);
    final sun = sunTimes(lat, lng, now);
    final offset = now.timeZoneOffset;
    DateTime? local(DateTime? utc) => utc?.add(offset);

    final labelStyle = AppTextStyles.menuItemDisabled(context).copyWith(fontSize: 14);
    final valueStyle = AppTextStyles.menuItem(context);
    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(label, style: labelStyle)),
              const SizedBox(width: 12),
              value,
            ],
          ),
        );
    Widget text(String value, [Key? key]) => Text(value, key: key, style: valueStyle);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: MenuPanel.background,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('ИНФОРМАЦИЯ', style: AppTextStyles.sectionHeader(context)),
                ),
                row('Координаты', text(coordinates, const Key('point_info_coordinates'))),
                row('Склонение (магнитное)', text(formatAngleEw(declination), const Key('point_info_declination'))),
                row('Конвергенция меридианов', text(formatAngleEw(convergence), const Key('point_info_convergence'))),
                row(
                  'Время восхода и заката',
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(AppIcons.sunrise, key: const Key('point_info_sunrise_icon'), size: 20, color: valueStyle.color),
                      const SizedBox(width: 4),
                      text(formatClock(local(sun.sunrise))),
                      const SizedBox(width: 12),
                      AppIcon(AppIcons.sunset, key: const Key('point_info_sunset_icon'), size: 20, color: valueStyle.color),
                      const SizedBox(width: 4),
                      text(formatClock(local(sun.sunset))),
                    ],
                  ),
                ),
                row('Часовой пояс', text(formatUtcOffset(offset))),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

Note: `local(...)` shifts the UTC event by the phone's current offset and the result is only used for `hour`/`minute` formatting. If `AppIcon` doesn't accept `key`, wrap it in `KeyedSubtree(key: …, child: AppIcon(...))` instead.

- [ ] **Step 5:** test → pass (plus `flutter test test/widgets` if an icon list test exists). **Step 6:** commit `feat(app): point info sheet with declination, convergence, sun times`.

---

### Task 5: Enable «i» in the crosshair card

**Files:** Modify `app/lib/map/crosshair_menu.dart`, `app/lib/map/map_screen.dart`; Test `app/test/map/crosshair_menu_test.dart`, `app/test/map/map_screen_test.dart`.

**Interfaces — Consumes:** Task 4 `showPointInfoSheet`. **Produces:** `CrosshairMenu(... required VoidCallback onInfo)`.

- [ ] **Step 1: Failing tests.**

In `crosshair_menu_test.dart`: add `onInfo: () => calls.add('info'),` to the `CrosshairMenu(...)` in `pump`; change the test «pin, camera and info are disabled placeholders» to check only pin and camera; add:

```dart
  testWidgets('info icon is active and calls back', (tester) async {
    final calls = await pump(tester);
    expect(tester.widget<IconButton>(find.byKey(const Key('crosshair_menu_info'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('crosshair_menu_info')));
    expect(calls, ['info']);
  });
```

In `map_screen_test.dart` add:

```dart
  testWidgets('«i» opens the ИНФОРМАЦИЯ sheet for the point under the crosshair', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(47.9958, 37.81465));
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('crosshair_menu_info')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
    expect(find.text('ИНФОРМАЦИЯ'), findsOneWidget);
    expect(find.text('47.99580, 37.81465'), findsOneWidget);
  });

  testWidgets('«i» before the map has settled reports the map is not ready', (tester) async {
    await pumpMap(tester);
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('crosshair_menu_info')));
    await tester.pumpAndSettle();
    expect(find.text('Карта ещё не готова'), findsOneWidget);
    expect(find.text('ИНФОРМАЦИЯ'), findsNothing);
  });
```

- [ ] **Step 2:** run both test files → failures (no `onInfo`).

- [ ] **Step 3: Implement.**

`crosshair_menu.dart`: add `required this.onInfo` / `final VoidCallback onInfo;`; in `_buildMain` replace `placeholderIcon('crosshair_menu_info', AppIcons.info)` with:

```dart
              IconButton(
                key: const Key('crosshair_menu_info'),
                onPressed: widget.onInfo,
                icon: AppIcon(AppIcons.info, size: 24, color: AppTextStyles.menuItem(context).color),
              ),
```

`map_screen.dart`: import `'point_info_sheet.dart'`; in the `CrosshairMenu(...)` add:

```dart
                  onInfo: () {
                    ref.read(crosshairMenuOpenProvider.notifier).close();
                    final center = _controller?.cameraPosition?.target ?? ref.read(mapCrosshairProvider);
                    if (center == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Карта ещё не готова')),
                      );
                      return;
                    }
                    showPointInfoSheet(
                      context,
                      point: center,
                      sk42: ref.read(menuTogglesProvider)[MenuToggle.settingsSk42Grid]!,
                    );
                  },
```

- [ ] **Step 4:** `flutter analyze` and `flutter test --timeout 60s` → clean, all pass. **Step 5:** commit `feat(app): «i» in the crosshair card opens the point info sheet`.

---

### Task 6: Ship and check on the device

- [ ] Final review; fix Critical/Important; ask the user before merging to `main` and pushing.
- [ ] `adb install -r`; on the phone tap the crosshair → «i»: title, five rows, sensible declination for Donetsk (about 9–10° В), convergence З west of 39° E, sunrise/sunset times of today in the phone's zone with the icons, `UTC+3`; coordinates switch with the СК-42 checkbox.
