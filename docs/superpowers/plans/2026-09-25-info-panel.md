# Info Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the top-left coordinate HUD with the three-line information panel: coordinates (WGS84 or СК-42), telemetry (track icon, numeric scale, zoom, scale bar), target distance/azimuth.

**Architecture:** Pure math in `sk42.dart` (datum shift + Gauss–Krüger) and `map_scale.dart` (scale, zoom, scale bar, target text). A presentational `InfoPanel` widget takes plain values and the toggle map. `MapScreen` feeds it from camera state, the target, recording state and `menuTogglesProvider`, and caps the map zoom at 20.

**Tech Stack:** Flutter 3.35.5, flutter_riverpod 3.x, maplibre_gl 0.26.2 (`minMaxZoomPreference`, `CameraPosition.zoom`).

**Spec:** `docs/superpowers/specs/2026-09-25-info-panel-design.md`

## Global Constraints

- Line 1 WGS84: `lat, lng` with 5 decimals (`47.99580, 37.81465`). СК-42: `X = 5318741 Y = 7411649` (whole metres, X northing, Y = zone·10⁶ + 500 000 + easting).
- СК-42 parameters: Krasovsky a = 6378245, f = 1/298.3; Helmert (СК-42 → WGS84, position vector, as PROJ `+towgs84=23.57,-140.95,-79.8,0,0.35,0.79,-0.22`), applied inversely; 6° zones by WGS84 longitude, central meridian 6·zone − 3, k0 = 1.
- Scale text: `< 10 000` → `1:5 000` (space thousands separator); else `1:14 546K` (thousands, space separator, `K`). Zoom text `6/20` (rounded zoom / 20). Map max zoom 20.
- Scale bar: largest 1/2/5·10ⁿ m that fits in 100 dp; label `200 км` (≥ 1000 m) or `50 м`.
- Target line: `→ 232,03 км 348.6°`; `< 1000 m` → `350 м`; azimuth crosshair → target, 0–360, one decimal with a point.
- Toggles: line 1 `settingsCenterCoordinates`; format `settingsSk42Grid`; scale+zoom `mapsMapScale`; bar `mapsScaleBar`; track icon `positioningRecordingStatus` (and only while recording); line 3 `waypointsTargetStatus` (and only with a target).
- Defaults change to on: `settingsCenterCoordinates`, `mapsMapScale`, `mapsScaleBar`.
- Style: light semi-transparent background, rounded corners, pronounced shadow. Block hidden when no line is shown.
- Run Flutter from `app/`, `--timeout 60s`. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Longitude exactly on a zone boundary (42.0°) must pick one zone consistently and not produce a Y from the wrong zone: Task 1 tests 41.99 / 42.01 and 42.0.
2. Latitude near the poles / zoom 0 must not produce `Infinity`/`NaN` scale text: Task 2 test at lat 85 and zoom 0.
3. A zoom like 19.6 must read `20/20`, never `21/20`: Task 2 test.
4. Target at the crosshair (0 m) shows `0 м` and an azimuth, not NaN: Task 2 test.
5. All toggles off hides the whole block (no empty card): Task 3 test.

---

### Task 1: WGS84 → СК-42 Gauss–Krüger

**Files:** Create `app/lib/map/sk42.dart`; Test `app/test/map/sk42_test.dart`.

**Interfaces — Produces:** `class Sk42Point { final double x; final double y; final int zone; }`, `Sk42Point toSk42(double lat, double lng)`.

- [ ] **Step 1: Failing test**

```dart
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
}
```

- [ ] **Step 2:** `flutter test test/map/sk42_test.dart --timeout 60s` → compile error.

- [ ] **Step 3: Implement** `app/lib/map/sk42.dart`:

```dart
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
```

- [ ] **Step 4:** same command → 7 pass.
- [ ] **Step 5:** commit `feat(app): WGS84 to СК-42 Gauss–Krüger conversion`.

---

### Task 2: Scale, zoom, scale bar and target text helpers

**Files:** Create `app/lib/map/map_scale.dart`; Test `app/test/map/map_scale_test.dart`.

**Interfaces — Produces:** `const double mapMaxZoom = 20`; `double metersPerDp(double zoom, double lat)`; `String scaleText(double zoom, double lat)`; `String zoomText(double zoom)`; `({double meters, double widthDp, String label}) scaleBar(double zoom, double lat, {double maxWidthDp = 100})`; `String targetText(double meters, double azimuth)`.

- [ ] **Step 1: Failing test**

```dart
import 'package:app/map/map_scale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('metersPerDp: 512-px tiles, halves per zoom level, shrinks with latitude', () {
    expect(metersPerDp(0, 0), closeTo(40075016.686 / 512, 0.001));
    expect(metersPerDp(1, 0), closeTo(metersPerDp(0, 0) / 2, 0.001));
    expect(metersPerDp(0, 60), closeTo(metersPerDp(0, 0) / 2, 0.01));
  });

  test('scaleText: full number under 10 000, thousands with K above', () {
    // 1 dp = 0.0254 / 160 m on a nominal 160-dpi screen.
    double zoomFor(double scale) {
      // zoom at lat 0 where metersPerDp / (0.0254 / 160) == scale
      return (40075016.686 / 512 / (scale * 0.0254 / 160)).log2();
    }

    expect(scaleText(zoomFor(5000), 0), '1:5 000');
    expect(scaleText(zoomFor(14546000), 0), '1:14 546K');
    expect(scaleText(zoomFor(9999), 0), '1:9 999');
    expect(scaleText(zoomFor(10000), 0), '1:10K');
  });

  test('scaleText stays finite at high latitude and zoom 0', () {
    expect(scaleText(0, 85), startsWith('1:'));
    expect(scaleText(0, 85), isNot(contains('Infinity')));
    expect(scaleText(0, 85), isNot(contains('NaN')));
  });

  test('zoomText rounds and never exceeds the max', () {
    expect(zoomText(6.2), '6/20');
    expect(zoomText(19.6), '20/20');
    expect(zoomText(20.4), '20/20');
    expect(zoomText(0), '0/20');
  });

  test('scaleBar picks 1/2/5 x 10^n within the width', () {
    for (final zoom in [3.0, 7.5, 12.0, 16.3, 19.0]) {
      final bar = scaleBar(zoom, 48);
      expect(bar.widthDp, lessThanOrEqualTo(100));
      expect(bar.widthDp, greaterThan(20));
      final mantissa = bar.meters / (10 * 1.0).pow((bar.meters.log10()).floor());
      expect([1, 2, 5], contains(mantissa.round()));
    }
    final km = scaleBar(5, 0);
    expect(km.label, endsWith(' км'));
    final m = scaleBar(18, 0);
    expect(m.label, endsWith(' м'));
  });

  test('targetText', () {
    expect(targetText(232030, 348.63), '→ 232,03 км 348.6°');
    expect(targetText(349.6, 12.04), '→ 350 м 12.0°');
    expect(targetText(0, 0), '→ 0 м 0.0°');
    expect(targetText(1000, 359.96), '→ 1,00 км 360.0°');
  });
}

extension on double {
  double log2() => math.log(this) / math.ln2;
  double log10() => math.log(this) / math.ln10;
  double pow(num e) => math.pow(this, e).toDouble();
}
```

Add `import 'dart:math' as math;` at the top of the test.

- [ ] **Step 2:** `flutter test test/map/map_scale_test.dart --timeout 60s` → compile error.

- [ ] **Step 3: Implement** `app/lib/map/map_scale.dart`:

```dart
import 'dart:math' as math;

/// The map never zooms past this; also the denominator of «6/20».
const double mapMaxZoom = 20;

const double _earthCircumference = 40075016.686;
const double _tileSize = 512;
// Nominal Android density: 160 dp per inch.
const double _metersPerDp = 0.0254 / 160;

/// Ground metres covered by one logical pixel at [zoom] and [lat]
/// (MapLibre native renders 512-px tiles in logical pixels).
double metersPerDp(double zoom, double lat) {
  final cosLat = math.cos(lat.clamp(-85.0, 85.0) * math.pi / 180);
  return _earthCircumference * cosLat / (_tileSize * math.pow(2, zoom));
}

String _grouped(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// «1:5 000» under 10 000, «1:14 546K» from 10 000 up.
String scaleText(double zoom, double lat) {
  final ratio = (metersPerDp(zoom, lat) / _metersPerDp).round();
  if (ratio < 10000) return '1:${_grouped(ratio)}';
  return '1:${_grouped((ratio / 1000).round())}K';
}

/// «6/20»: rounded current zoom over the map's maximum.
String zoomText(double zoom) {
  final current = zoom.round().clamp(0, mapMaxZoom.toInt());
  return '$current/${mapMaxZoom.toInt()}';
}

/// The largest 1/2/5·10ⁿ-metre distance that fits in [maxWidthDp].
({double meters, double widthDp, String label}) scaleBar(double zoom, double lat, {double maxWidthDp = 100}) {
  final perDp = metersPerDp(zoom, lat);
  final maxMeters = perDp * maxWidthDp;
  final power = math.pow(10, (math.log(maxMeters) / math.ln10).floor()).toDouble();
  var meters = power;
  for (final step in const [5, 2, 1]) {
    if (step * power <= maxMeters) {
      meters = step * power;
      break;
    }
  }
  final label = meters >= 1000 ? '${(meters / 1000).round()} км' : '${meters.round()} м';
  return (meters: meters, widthDp: meters / perDp, label: label);
}

/// «→ 232,03 км 348.6°»; under a kilometre «→ 350 м 12.0°».
String targetText(double meters, double azimuth) {
  final distance = meters < 999.995
      ? '${meters.round()} м'
      : '${(meters / 1000).toStringAsFixed(2).replaceAll('.', ',')} км';
  return '→ $distance ${azimuth.toStringAsFixed(1)}°';
}
```

Note on `targetText(349.6, …)`: `349.6.round()` is 350 → «350 м» as required. `999.995` keeps «1000 м» from appearing (it becomes «1,00 км»).

- [ ] **Step 4:** same command → all pass.
- [ ] **Step 5:** commit `feat(app): map scale, zoom, scale bar and target text helpers`.

---

### Task 3: InfoPanel widget and new toggle defaults

**Files:** Create `app/lib/map/info_panel.dart`; Modify `app/lib/menu/menu_toggles.dart` (three defaults); Test `app/test/map/info_panel_test.dart`, `app/test/menu/menu_toggles_test.dart` (one assertion).

**Interfaces — Consumes:** Task 1 `toSk42`, Task 2 helpers, `bearingDegrees`/`distanceMeters` (`geo_utils.dart`), `MenuToggle`.
**Produces:** `InfoPanel({Key? key, required LatLng center, required double zoom, LatLng? target, required bool recording, required Map<MenuToggle, bool> toggles})`; keys `info_panel`, `info_line_coordinates`, `info_line_telemetry`, `info_line_target`, `info_track_icon`, `info_scale_text`, `info_zoom_text`, `info_scale_bar`.

- [ ] **Step 1: Failing tests**

In `app/test/menu/menu_toggles_test.dart`, in the test «starts with the mockup defaults», add:

```dart
    expect(state[MenuToggle.settingsCenterCoordinates], isTrue);
    expect(state[MenuToggle.mapsMapScale], isTrue);
    expect(state[MenuToggle.mapsScaleBar], isTrue);
```

Create `app/test/map/info_panel_test.dart`:

```dart
import 'package:app/map/info_panel.dart';
import 'package:app/menu/menu_toggles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  const center = LatLng(47.99580, 37.81465);
  Map<MenuToggle, bool> toggles([Map<MenuToggle, bool> overrides = const {}]) => {
        for (final t in MenuToggle.values) t: t.defaultValue,
        MenuToggle.settingsCenterCoordinates: true,
        MenuToggle.mapsMapScale: true,
        MenuToggle.mapsScaleBar: true,
        ...overrides,
      };

  Future<void> pump(
    WidgetTester tester, {
    Map<MenuToggle, bool>? t,
    LatLng? target,
    bool recording = false,
    double zoom = 6.2,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: InfoPanel(center: center, zoom: zoom, target: target, recording: recording, toggles: t ?? toggles()),
          ),
        ),
      ),
    );
  }

  testWidgets('line 1: WGS84 degrees by default, СК-42 X/Y with the toggle', (tester) async {
    await pump(tester);
    expect(find.text('47.99580, 37.81465'), findsOneWidget);

    await pump(tester, t: toggles({MenuToggle.settingsSk42Grid: true}));
    expect(find.text('X = 5318741 Y = 7411649'), findsOneWidget);
  });

  testWidgets('line 1 follows «Координаты центра экрана»', (tester) async {
    await pump(tester, t: toggles({MenuToggle.settingsCenterCoordinates: false}));
    expect(find.byKey(const Key('info_line_coordinates')), findsNothing);
  });

  testWidgets('line 2: scale and zoom follow «Масштаб карты», bar follows «Масштабная линейка»', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('info_scale_text')), findsOneWidget);
    expect(find.text('6/20'), findsOneWidget);
    expect(find.byKey(const Key('info_scale_bar')), findsOneWidget);

    await pump(tester, t: toggles({MenuToggle.mapsMapScale: false}));
    expect(find.byKey(const Key('info_scale_text')), findsNothing);
    expect(find.byKey(const Key('info_zoom_text')), findsNothing);
    expect(find.byKey(const Key('info_scale_bar')), findsOneWidget);

    await pump(tester, t: toggles({MenuToggle.mapsScaleBar: false}));
    expect(find.byKey(const Key('info_scale_bar')), findsNothing);
  });

  testWidgets('track icon only while recording and «Статус записи трека» is on', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('info_track_icon')), findsNothing);
    await pump(tester, recording: true);
    expect(find.byKey(const Key('info_track_icon')), findsOneWidget);
    await pump(tester, recording: true, t: toggles({MenuToggle.positioningRecordingStatus: false}));
    expect(find.byKey(const Key('info_track_icon')), findsNothing);
  });

  testWidgets('line 3 only with a target and «Статус цели»', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('info_line_target')), findsNothing);

    await pump(tester, target: center);
    expect(find.byKey(const Key('info_line_target')), findsOneWidget);
    expect(find.text('→ 0 м 0.0°'), findsOneWidget);

    await pump(tester, target: center, t: toggles({MenuToggle.waypointsTargetStatus: false}));
    expect(find.byKey(const Key('info_line_target')), findsNothing);
  });

  testWidgets('everything off hides the whole block', (tester) async {
    await pump(
      tester,
      t: toggles({
        MenuToggle.settingsCenterCoordinates: false,
        MenuToggle.mapsMapScale: false,
        MenuToggle.mapsScaleBar: false,
      }),
    );
    expect(find.byKey(const Key('info_panel')), findsNothing);
  });

  testWidgets('style: semi-transparent light background, rounded, shadow', (tester) async {
    await pump(tester);
    final box = tester.widget<Container>(find.byKey(const Key('info_panel')));
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color!.a, lessThan(1));
    expect(decoration.color!.a, greaterThan(0.5));
    expect(decoration.borderRadius, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
  });
}
```

- [ ] **Step 2:** `flutter test test/map/info_panel_test.dart test/menu/menu_toggles_test.dart --timeout 60s` → compile error / default assertions fail.

- [ ] **Step 3: Implement**

In `app/lib/menu/menu_toggles.dart` change `settingsCenterCoordinates(false)` → `(true)`, `mapsMapScale(false)` → `(true)`, `mapsScaleBar(false)` → `(true)`.

Create `app/lib/map/info_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app_icons.dart';
import '../menu/menu_toggles.dart';
import '../widgets/app_icon.dart';
import 'geo_utils.dart';
import 'map_scale.dart';
import 'sk42.dart';

/// Top-left overlay: centre coordinates, telemetry (recording icon, scale,
/// zoom, scale bar) and, with a «Задать цель» target, its distance and
/// azimuth. Each part follows its menu toggle; nothing shown → no block.
class InfoPanel extends StatelessWidget {
  const InfoPanel({
    super.key,
    required this.center,
    required this.zoom,
    this.target,
    required this.recording,
    required this.toggles,
  });

  final LatLng center;
  final double zoom;
  final LatLng? target;
  final bool recording;
  final Map<MenuToggle, bool> toggles;

  bool _on(MenuToggle toggle) => toggles[toggle] ?? toggle.defaultValue;

  @override
  Widget build(BuildContext context) {
    const textColor = Color(0xFF16181A);
    const style = TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500);
    final lines = <Widget>[];

    if (_on(MenuToggle.settingsCenterCoordinates)) {
      final String text;
      if (_on(MenuToggle.settingsSk42Grid)) {
        final p = toSk42(center.latitude, center.longitude);
        text = 'X = ${p.x.round()} Y = ${p.y.round()}';
      } else {
        text = '${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}';
      }
      lines.add(Text(text, key: const Key('info_line_coordinates'), style: style.copyWith(fontWeight: FontWeight.w700)));
    }

    final showTrack = recording && _on(MenuToggle.positioningRecordingStatus);
    final showScale = _on(MenuToggle.mapsMapScale);
    final showBar = _on(MenuToggle.mapsScaleBar);
    if (showTrack || showScale || showBar) {
      final bar = scaleBar(zoom, center.latitude);
      lines.add(
        Row(
          key: const Key('info_line_telemetry'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTrack) ...[
              const Icon(Icons.timeline, key: Key('info_track_icon'), size: 18, color: textColor),
              const SizedBox(width: 6),
            ],
            if (showScale) ...[
              Text(scaleText(zoom, center.latitude), key: const Key('info_scale_text'), style: style),
              const SizedBox(width: 8),
              Text(zoomText(zoom), key: const Key('info_zoom_text'), style: style),
              const SizedBox(width: 8),
            ],
            if (showBar)
              Column(
                key: const Key('info_scale_bar'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bar.label, style: style.copyWith(fontSize: 12)),
                  Container(
                    width: bar.widthDp,
                    height: 4,
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: textColor, width: 1.5),
                        right: BorderSide(color: textColor, width: 1.5),
                        bottom: BorderSide(color: textColor, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    }

    final target = this.target;
    if (target != null && _on(MenuToggle.waypointsTargetStatus)) {
      final meters = distanceMeters(center.latitude, center.longitude, target.latitude, target.longitude);
      final azimuth = meters == 0
          ? 0.0
          : bearingDegrees(center.latitude, center.longitude, target.latitude, target.longitude);
      lines.add(
        Row(
          key: const Key('info_line_target'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(AppIcons.flag, size: 18, color: textColor),
            const SizedBox(width: 6),
            Text(targetText(meters, azimuth), style: style),
          ],
        ),
      );
    }

    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('info_panel'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[if (i > 0) const SizedBox(height: 4), lines[i]],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4:** same command → all pass.
- [ ] **Step 5:** commit `feat(app): info panel widget; coordinate and scale toggles on by default`.

---

### Task 4: Use InfoPanel in MapScreen, cap zoom at 20

**Files:** Modify `app/lib/map/map_screen.dart`; Test `app/test/map/map_screen_test.dart`.

**Interfaces — Consumes:** Task 3 `InfoPanel`, Task 2 `mapMaxZoom`, `trackRecordingControllerProvider`, `TrackRecordingActive`.

- [ ] **Step 1: Failing test** — add to `map_screen_test.dart`:

```dart
  testWidgets('the map is capped at zoom 20 and the old coordinate HUD is gone', (tester) async {
    await pumpMap(tester);
    final map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));
    expect(map.minMaxZoomPreference.maxZoom, 20);
    expect(find.byKey(const Key('coordinate_hud')), findsNothing);
  });
```

- [ ] **Step 2:** run `flutter test test/map/map_screen_test.dart --timeout 60s` → the new test fails (no max zoom).

- [ ] **Step 3: Implement** in `map_screen.dart`:
1. Imports: add `'info_panel.dart'`, `'map_scale.dart'`, `'../tracks/track_recording_controller.dart'` (skip if already imported).
2. Field next to `_crosshairPosition`: `double _cameraZoom = initialMapCamera.zoom;`
3. `_onCameraIdle`: after reading `position`, set both in one `setState`: `setState(() { _crosshairPosition = position.target; _cameraZoom = position.zoom; });` (replace the existing `setState(() => _crosshairPosition = position.target);`).
4. `MapLibreMap(...)`: add `minMaxZoomPreference: const MinMaxZoomPreference(null, mapMaxZoom),`.
5. Replace the HUD child `_CoordinateHud(target: _crosshairPosition!, myLocation: _myLocation)` with:

```dart
InfoPanel(
  center: _liveCenter ?? _crosshairPosition!,
  zoom: _cameraZoom,
  target: target,
  recording: ref.watch(trackRecordingControllerProvider) is TrackRecordingActive,
  toggles: toggles,
),
```
(`target` and `toggles` are the locals already read at the top of `build`.)
6. Delete the `_CoordinateHud` class and any imports that become unused (`flutter analyze` lists them); update the comment above the HUD `Positioned` if it names the old HUD.

- [ ] **Step 4:** `flutter analyze` and `flutter test --timeout 60s` → clean, all pass.
- [ ] **Step 5:** commit `feat(app): information panel replaces the coordinate HUD; max zoom 20`.

---

### Task 5: Ship and check on the device

- [ ] Final review, fixes, then ask the user before merging to `main` and pushing.
- [ ] Install with `adb install -r` (key is stable now).
- [ ] On the phone: line 1 in degrees, then СК-42 after ticking the checkbox; scale/zoom/bar change with «+»/«−»; track icon while recording; line 3 with a target; toggles hide lines (the user's saved toggles may need ticking once).
