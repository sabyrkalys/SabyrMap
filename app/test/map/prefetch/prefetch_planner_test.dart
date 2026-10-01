import 'package:app/map/prefetch/prefetch_planner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng, LatLngBounds;

void main() {
  // About one phone screen at z13 over the Carpathians (vector tiles are
  // 512 px, so a ~400 dp wide screen is under one tile wide).
  final visible = LatLngBounds(southwest: const LatLng(48.13, 24.47), northeast: const LatLng(48.18, 24.505));

  double centreLat(LatLngBounds b) => (b.southwest.latitude + b.northeast.latitude) / 2;
  double centreLon(LatLngBounds b) => (b.southwest.longitude + b.northeast.longitude) / 2;
  double width(LatLngBounds b) => b.northeast.longitude - b.southwest.longitude;

  test('tileCount counts the tiles that cover an area', () {
    final world = LatLngBounds(southwest: const LatLng(-85, -180), northeast: const LatLng(85, 179.99));
    expect(tileCount(world, 0), 1);
    expect(tileCount(world, 2), 16);
    expect(tileCount(visible, 13), greaterThan(1));
  });

  test('the ring is 1.5× the screen at the current zoom, plus the centre one zoom deeper', () {
    final parts = planPrefetch(visible: visible, zoom: 13.4);

    expect(parts.map((p) => p.zoom), [13, 14]);
    final ring = parts.first.bounds;
    expect(width(ring), closeTo(width(visible) * 1.5, 1e-9));
    expect(centreLon(ring), closeTo(centreLon(visible), 1e-9));
    expect(width(parts[1].bounds), closeTo(width(visible) * 0.5, 1e-9));
    expect(parts.fold<int>(0, (sum, p) => sum + p.tiles), lessThanOrEqualTo(60));
  });

  test('the ring leans towards where the map was moving', () {
    // The map moved east: the previous centre is west of the current one.
    final parts = planPrefetch(visible: visible, zoom: 13, previousCenter: const LatLng(48.155, 24.45));

    final ring = parts.first.bounds;
    expect(centreLon(ring), greaterThan(centreLon(visible)));
    expect(centreLat(ring), closeTo(centreLat(visible), 1e-6));
    // Still covers the whole screen.
    expect(ring.southwest.longitude, lessThanOrEqualTo(visible.southwest.longitude));
    expect(ring.northeast.longitude, greaterThan(visible.northeast.longitude));
  });

  test('the tile cap drops the deeper zoom first, then the ring, then everything', () {
    // A bigger area (a tablet), so ring, screen and centre differ in tiles.
    final big = LatLngBounds(southwest: const LatLng(48.10, 24.40), northeast: const LatLng(48.22, 24.58));
    final full = planPrefetch(visible: big, zoom: 13, maxTiles: 1000);
    expect(full.map((p) => p.zoom), [13, 14]);
    final ringTiles = full.first.tiles;
    final screenTiles = tileCount(big, 13);
    expect(ringTiles, greaterThan(screenTiles), reason: 'precondition: the ring is bigger than the screen');

    expect(planPrefetch(visible: big, zoom: 13, maxTiles: ringTiles).map((p) => p.zoom), [13]);
    expect(planPrefetch(visible: big, zoom: 13, maxTiles: ringTiles - 1).single.bounds, big);
    expect(planPrefetch(visible: big, zoom: 13, maxTiles: screenTiles - 1), isEmpty);
  });

  test('no deeper zoom past the map\'s max zoom', () {
    expect(planPrefetch(visible: visible, zoom: 14.2, maxZoom: 14).map((p) => p.zoom), [14]);
  });
}
