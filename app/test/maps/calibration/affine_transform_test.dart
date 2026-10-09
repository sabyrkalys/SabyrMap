import 'package:app/maps/calibration/affine_transform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identity', () {
    expect(AffineTransform.identity.apply(12, -3), (12.0, -3.0));
    expect(AffineTransform.identity.inverse(), AffineTransform.identity);
  });

  test('apply on a known rectangle', () {
    // 1000×500 пикселей → 30..31° долготы, 51..50° широты (Y вниз).
    const t = AffineTransform(a: 0.001, b: 0, c: 30, d: 0, e: -0.002, f: 51);
    expect(t.apply(0, 0), (30.0, 51.0));
    final (lon, lat) = t.apply(1000, 500);
    expect(lon, closeTo(31, 1e-12));
    expect(lat, closeTo(50, 1e-12));
  });

  test('inverse undoes apply; degenerate has none', () {
    const t = AffineTransform(a: 0.001, b: 0.0002, c: 30, d: -0.0001, e: -0.002, f: 51);
    final (lon, lat) = t.apply(123, 456);
    final (x, y) = t.inverse()!.apply(lon, lat);
    expect(x, closeTo(123, 1e-6));
    expect(y, closeTo(456, 1e-6));
    expect(const AffineTransform(a: 1, b: 2, c: 0, d: 2, e: 4, f: 0).inverse(), isNull);
  });
}
