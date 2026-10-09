import 'package:app/maps/file_maps/bounds_intersector.dart';
import 'package:app/maps/file_maps/map_bounds.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  const a = MapBounds(northLat: 51, southLat: 50, westLon: 30, eastLon: 31);
  const b = MapBounds(northLat: 50.5, southLat: 49, westLon: 30.5, eastLon: 32);
  const far = MapBounds(northLat: 10, southLat: 9, westLon: 10, eastLon: 11);

  test('a point inside, on the edge and outside', () {
    expect(BoundsIntersector.boundsCoverPoint(a, loc(50.5, 30.5)), isTrue);
    expect(BoundsIntersector.boundsCoverPoint(a, loc(51, 31)), isTrue);
    expect(BoundsIntersector.boundsCoverPoint(a, loc(51.01, 30.5)), isFalse);
  });

  test('intersection of two rectangles; none for far ones', () {
    expect(a.intersects(b), isTrue);
    expect(a.intersection(b), const MapBounds(northLat: 50.5, southLat: 50, westLon: 30.5, eastLon: 31));
    expect(a.intersects(far), isFalse);
    expect(a.intersection(far), isNull);
    const invalid = MapBounds(northLat: 1, southLat: 2, westLon: 0, eastLon: 1);
    expect(a.intersection(invalid), isNull);
  });

  test('union, area, boundsOf, expand', () {
    expect(a.union(b), const MapBounds(northLat: 51, southLat: 49, westLon: 30, eastLon: 32));
    expect(a.areaSquareDegrees, 1);
    expect(
      BoundsIntersector.boundsOf([loc(50, 30), loc(51, 32), loc(49, 31)]),
      const MapBounds(northLat: 51, southLat: 49, westLon: 30, eastLon: 32),
    );
    expect(() => BoundsIntersector.boundsOf(const []), throwsArgumentError);
    expect(BoundsIntersector.expand(a, 0.5), const MapBounds(northLat: 51.5, southLat: 49.5, westLon: 29.5, eastLon: 31.5));
    expect(BoundsIntersector.expand(const MapBounds(northLat: 89.5, southLat: 0, westLon: 179, eastLon: 179.5), 1).northLat, 90);
  });
}
