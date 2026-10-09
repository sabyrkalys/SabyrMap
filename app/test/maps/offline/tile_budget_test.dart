import 'package:app/maps/file_maps/file_map_scanner.dart';
import 'package:app/maps/file_maps/map_bounds.dart';
import 'package:app/maps/offline/tile_budget.dart';
import 'package:flutter_test/flutter_test.dart';

/// Границы тайла (x, y) на зуме z.
MapBounds tile(int x, int y, int z) => MapBounds(
  northLat: FileMapScanner.tileLat(y, z),
  southLat: FileMapScanner.tileLat(y + 1, z),
  westLon: FileMapScanner.tileLon(x, z),
  eastLon: FileMapScanner.tileLon(x + 1, z),
);

void main() {
  test('one tile, then 1 + 4 + 16 on the next zooms', () {
    final b = tile(600, 345, 10);
    expect(TileBudget(minZoom: 10, maxZoom: 10, bounds: b).estimateTileCount(), 1);
    expect(TileBudget(minZoom: 10, maxZoom: 12, bounds: b).estimateTileCount(), 1 + 4 + 16);
  });

  test('the whole world: 4^z per zoom', () {
    const world = MapBounds(northLat: 85.06, southLat: -85.06, westLon: -180, eastLon: 180);
    expect(TileBudget(minZoom: 0, maxZoom: 2, bounds: world).estimateTileCount(), 1 + 4 + 16);
  });

  test('1°×1° near Kyiv on zoom 10 spans several tiles', () {
    const b = MapBounds(northLat: 51, southLat: 50, westLon: 30, eastLon: 31);
    final budget = TileBudget(minZoom: 10, maxZoom: 10, bounds: b);
    final r = budget.tileRange(10);
    expect((r.minX, r.maxX, r.minY, r.maxY), (597, 600, 342, 347));
    expect(budget.estimateTileCount(), 24);
  });

  test('zoom range is validated', () {
    const b = MapBounds(northLat: 1, southLat: 0, westLon: 0, eastLon: 1);
    expect(() => TileBudget(minZoom: 5, maxZoom: 4, bounds: b), throwsArgumentError);
    expect(() => TileBudget(minZoom: -1, maxZoom: 4, bounds: b), throwsArgumentError);
  });

  test('empty or invalid bounds give 0', () {
    const line = MapBounds(northLat: 1, southLat: 1, westLon: 0, eastLon: 1);
    const inverted = MapBounds(northLat: 0, southLat: 1, westLon: 0, eastLon: 1);
    expect(TileBudget(minZoom: 0, maxZoom: 5, bounds: line).estimateTileCount(), 0);
    expect(TileBudget(minZoom: 0, maxZoom: 5, bounds: inverted).estimateTileCount(), 0);
  });
}
