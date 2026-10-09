import 'package:app/maps/dem/dem_coverage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  test('(0.5, 0.5) is tile 0, 0', () {
    final c = DemCoverage.forLocation(loc(0.5, 0.5));
    expect((c.tileX, c.tileY), (0, 0));
    expect(c.isCovered, isFalse);
  });

  test('longitude −1.0, latitude 1.0 is tile −1, 1', () {
    final c = DemCoverage.forLocation(loc(1.0, -1.0));
    expect((c.tileX, c.tileY), (-1, 1));
  });

  test('negative fractions go to the lower tile; file names', () {
    expect(DemCoverage.forLocation(loc(-0.2, -0.2)).fileName, 'S01W001.hgt');
    expect(DemCoverage.forLocation(loc(50.4, 30.5)).fileName, 'N50E030.hgt');
  });
}
