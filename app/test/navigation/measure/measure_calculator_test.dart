import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/navigation/measure/measure_calculator.dart';
import 'package:app/navigation/measure/measure_color_scheme.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  final points = [loc(0, 0), loc(1, 0), loc(1, 1)];

  test('3 points give 2 segments with distance, azimuth and colour', () {
    final segments = MeasureCalculator.buildSegments(points);
    expect(segments, hasLength(2));
    expect(segments.first.from, points[0]);
    expect(segments.first.to, points[1]);
    expect(segments.first.distanceMeters, closeTo(Haversine.distance(points[0], points[1]), 1e-9));
    expect(segments.first.azimuthDeg, closeTo(0, 1e-9));
    expect(segments.first.segmentColor, MeasureColorScheme.red);
    expect(MeasureCalculator.buildSegments([loc(0, 0)]), isEmpty);
    expect(MeasureCalculator.buildSegments(const []), isEmpty);
  });

  test('total distance is the sum of segments', () {
    final sum = MeasureCalculator.buildSegments(points).fold(0.0, (a, s) => a + s.distanceMeters);
    expect(MeasureCalculator.totalDistance(points), closeTo(sum, 1e-6));
  });

  test('colours: north red, south blue, east and west in between', () {
    expect(MeasureColorScheme.colorFor(0), MeasureColorScheme.red);
    expect(MeasureColorScheme.colorFor(44), MeasureColorScheme.red);
    expect(MeasureColorScheme.colorFor(350), MeasureColorScheme.red);
    expect(MeasureColorScheme.colorFor(180), MeasureColorScheme.blue);
    expect(MeasureColorScheme.colorFor(136), MeasureColorScheme.blue);
    final east = MeasureColorScheme.colorFor(90);
    final west = MeasureColorScheme.colorFor(270);
    expect(east, west);
    expect(east, isNot(anyOf(MeasureColorScheme.red, MeasureColorScheme.blue)));
    expect(east, 0xFF800080);
    expect((MeasureColorScheme.colorFor(60) >> 16) & 0xFF, greaterThan((east >> 16) & 0xFF));
  });
}
