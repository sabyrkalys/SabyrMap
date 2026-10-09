import 'package:app/maps/calibration/affine_transform.dart';
import 'package:app/maps/calibration/calibration_controller.dart';
import 'package:app/maps/calibration/calibration_math.dart';
import 'package:app/maps/calibration/calibration_point.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  const truth = AffineTransform(a: 0.001, b: 0.0001, c: 30, d: -0.00005, e: -0.002, f: 51);
  CalibrationPoint pt(double x, double y) {
    final (lon, lat) = truth.apply(x, y);
    return CalibrationPoint(imageX: x, imageY: y, worldLon: lon, worldLat: lat);
  }

  test('3 points give the exact transform', () {
    final t = CalibrationMath.transformFor([pt(0, 0), pt(1000, 0), pt(0, 800)])!;
    for (final (got, want) in [(t.a, truth.a), (t.b, truth.b), (t.c, truth.c), (t.d, truth.d), (t.e, truth.e), (t.f, truth.f)]) {
      expect(got, closeTo(want, 1e-9));
    }
  });

  test('fewer than 3 points or a line give null', () {
    expect(CalibrationMath.transformFor([pt(0, 0), pt(10, 10)]), isNull);
    expect(CalibrationMath.transformFor([pt(0, 0), pt(10, 10), pt(20, 20)]), isNull);
  });

  test('4 points: least squares, small residual with noise', () {
    final noisy = [pt(0, 0), pt(1000, 0), pt(0, 800), pt(1000, 800).copyWith(worldLon: truth.apply(1000, 800).$1 + 1e-5)];
    final t = CalibrationMath.transformFor(noisy)!;
    expect(CalibrationMath.maxResidualDegrees(t, noisy), lessThan(1e-5));
  });

  test('back projection: world → image', () {
    final t = CalibrationMath.transformFor([pt(0, 0), pt(1000, 0), pt(0, 800)])!;
    final (lon, lat) = t.apply(250, 640);
    final (x, y) = CalibrationMath.worldToImage(t, lon, lat)!;
    expect(x, closeTo(250, 1e-6));
    expect(y, closeTo(640, 1e-6));
    final bounds = CalibrationMath.boundsOf(t, 1000, 800);
    expect(bounds.westLon, closeTo(30, 1e-9));
  });

  test('controller: points, screen centre, finish saves, less than 3 fails', () async {
    final settings = await freshMapsSettings();
    final c = CalibrationController(settings);
    await c.start('/maps/scan.png');
    expect(c.state.isActive, isTrue);
    c.addPoint(pt(0, 0));
    c.addPoint(pt(1000, 0));
    expect(c.state.isReady, isFalse);
    expect(c.finish, throwsStateError);
    c.addPoint(const CalibrationPoint(imageX: 0, imageY: 800, worldLon: 0, worldLat: 0));
    c.applyScreenCenter(loc(truth.apply(0, 800).$2, truth.apply(0, 800).$1));
    expect(c.state.isReady, isTrue);
    c.addPoint(pt(1000, 800));
    expect(() => c.addPoint(pt(5, 5)), throwsStateError);
    c.removeLastPoint();
    c.setOpacity(2);
    expect(c.state.opacity, 1);
    final t = await c.finish();
    expect(t.c, closeTo(30, 1e-9));
    expect(c.state.isActive, isFalse);

    final again = CalibrationController(settings);
    await again.start('/maps/scan.png');
    expect(again.state.points, hasLength(3));
    again.cancel();
    expect(again.state.isActive, isFalse);
  });
}
