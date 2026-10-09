import 'package:app/landmarks/composite/operations/polygon_ops.dart';
import 'package:app/landmarks/models/landmark_area.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final poly = AreaPolygon(outline: [loc(0, 0), loc(0, 1), loc(1, 1)]);

  test('addOutlinePoint at the end, at 0, into an empty outline', () {
    expect(PolygonOps.addOutlinePoint(poly, loc(1, 0)).outline.last, loc(1, 0));
    expect(PolygonOps.addOutlinePoint(poly, loc(1, 0), atIndex: 0).outline.first, loc(1, 0));
    expect(PolygonOps.addOutlinePoint(const AreaPolygon(), loc(1, 0)).outline, [loc(1, 0)]);
    expect(() => PolygonOps.addOutlinePoint(poly, loc(1, 0), atIndex: 4), throwsRangeError);
  });

  test('remove and move points; first and last', () {
    expect(PolygonOps.removeOutlinePoint(poly, 0).outline, [loc(0, 1), loc(1, 1)]);
    expect(PolygonOps.removeOutlinePoint(poly, 2).outline, [loc(0, 0), loc(0, 1)]);
    expect(PolygonOps.moveOutlinePoint(poly, 2, loc(2, 2)).outline.last, loc(2, 2));
    expect(() => PolygonOps.removeOutlinePoint(const AreaPolygon(), 0), throwsRangeError);
  });

  test('reorderOutline', () {
    expect(PolygonOps.reorderOutline(poly, 0, 2).outline, [loc(0, 1), loc(1, 1), loc(0, 0)]);
    expect(() => PolygonOps.reorderOutline(poly, 0, 3), throwsRangeError);
  });

  test('holes', () {
    final withHole = PolygonOps.addHole(poly, [loc(0.1, 0.1), loc(0.1, 0.2), loc(0.2, 0.2)]);
    expect(withHole.holes, hasLength(1));
    expect(withHole.outline, poly.outline);
    expect(PolygonOps.removeHole(withHole, 0).holes, isEmpty);
    expect(() => PolygonOps.removeHole(poly, 0), throwsRangeError);
  });
}
