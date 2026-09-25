import 'dart:math' as math;

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
    expect(zoomText(6.2), '6/22');
    expect(zoomText(19.6), '20/22');
    expect(zoomText(22.4), '22/22');
    expect(zoomText(0), '0/22');
  });

  test('scaleBar picks 1/2/5 x 10^n within the width', () {
    for (final zoom in [3.0, 7.5, 12.0, 16.3, 19.0]) {
      final bar = scaleBar(zoom, 48);
      expect(bar.widthDp, lessThanOrEqualTo(100));
      expect(bar.widthDp, greaterThan(20));
      final mantissa = bar.meters / (10 * 1.0).pow((bar.meters.log10() + 1e-9).floor());
      expect([1, 2, 5], contains(mantissa.round()));
    }
    final km = scaleBar(5, 0);
    expect(km.label, endsWith(' км'));
    final m = scaleBar(18, 0);
    expect(m.label, endsWith(' м'));
  });

  test('targetText', () {
    expect(targetText(232030, 348.63), '→ 232,03 км 348.6°');
    expect(targetText(349.6, 12.04), '→ 349,6 м 12.0°');
    expect(targetText(1.26, 90), '→ 1,3 м 90.0°');
    expect(targetText(0, 0), '→ 0,0 м 0.0°');
    expect(targetText(1000, 359.96), '→ 1,00 км 360.0°');
  });

  test('at the max zoom the scale bar reaches 1 m, on the equator and at 48°', () {
    expect(scaleBar(mapMaxZoom, 0).label, '1 м');
    expect(scaleBar(mapMaxZoom, 48).label, '1 м');
  });
}

extension on double {
  double log2() => math.log(this) / math.ln2;
  double log10() => math.log(this) / math.ln10;
  double pow(num e) => math.pow(this, e).toDouble();
}
