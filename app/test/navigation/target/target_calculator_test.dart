import 'package:app/navigation/target/target_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  test('1° of longitude at the equator is about 111 km', () {
    final info = TargetCalculator.compute(source: loc(0, 0), target: loc(0, 1));
    expect(info.distanceMeters, closeTo(111195, 200));
  });

  test('azimuth N/E/S/W and the reverse azimuth', () {
    expect(TargetCalculator.compute(source: loc(0, 0), target: loc(1, 0)).azimuthDeg, closeTo(0, 1e-9));
    expect(TargetCalculator.compute(source: loc(0, 0), target: loc(0, 1)).azimuthDeg, closeTo(90, 1e-9));
    expect(TargetCalculator.compute(source: loc(1, 0), target: loc(0, 0)).azimuthDeg, closeTo(180, 1e-9));
    final west = TargetCalculator.compute(source: loc(0, 1), target: loc(0, 0));
    expect(west.azimuthDeg, closeTo(270, 1e-9));
    expect(west.reverseAzimuthDeg, closeTo(90, 1e-9));
  });

  test('elevation difference and slope', () {
    final info = TargetCalculator.compute(
      source: loc(0, 0),
      target: loc(0, 0.01),
      sourceElevation: 100,
      targetElevation: 150,
    );
    expect(info.elevationDiffMeters, 50);
    expect(info.slopePercent, closeTo(100 * 50 / info.distanceMeters, 1e-9));
  });

  test('ETA with speed; none without', () {
    final info = TargetCalculator.compute(source: loc(0, 0), target: loc(0, 0.01), speedMps: 2);
    expect(info.etaSeconds, (info.distanceMeters / 2).round());
    expect(info.speedMps, 2);
    expect(TargetCalculator.compute(source: loc(0, 0), target: loc(0, 0.01), speedMps: 0).etaSeconds, isNull);
  });

  test('without heights there is no difference or slope; same point has no slope', () {
    final info = TargetCalculator.compute(source: loc(0, 0), target: loc(0, 1), sourceElevation: 10);
    expect(info.elevationDiffMeters, isNull);
    expect(info.slopePercent, isNull);
    final same = TargetCalculator.compute(source: loc(0, 0), target: loc(0, 0), sourceElevation: 1, targetElevation: 2);
    expect(same.slopePercent, isNull);
  });

  test('heights are read from location values', () {
    expect(TargetCalculator.elevationOf(loc(0, 0, ele: 312.5)), 312.5);
    expect(TargetCalculator.elevationOf(loc(0, 0)), isNull);
  });
}
