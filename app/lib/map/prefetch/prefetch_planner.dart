import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart' show LatLng, LatLngBounds;

/// One piece of a prefetch: an area at one zoom.
class PrefetchPart {
  const PrefetchPart(this.bounds, this.zoom, this.tiles);

  final LatLngBounds bounds;
  final int zoom;

  /// z/x/y tiles that cover [bounds] at [zoom].
  final int tiles;
}

int _lonToX(double lon, int z) {
  final n = 1 << z;
  return ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
}

int _latToY(double lat, int z) {
  final n = 1 << z;
  final r = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
  return y.floor().clamp(0, n - 1);
}

/// Tiles covering [bounds] at zoom [z].
int tileCount(LatLngBounds bounds, int z) {
  final sw = bounds.southwest;
  final ne = bounds.northeast;
  final cols = _lonToX(ne.longitude, z) - _lonToX(sw.longitude, z) + 1;
  final rows = _latToY(sw.latitude, z) - _latToY(ne.latitude, z) + 1;
  return cols * rows;
}

LatLngBounds _scaled(LatLngBounds b, double factor, {double shiftLat = 0, double shiftLon = 0}) {
  final cLat = (b.southwest.latitude + b.northeast.latitude) / 2 + shiftLat;
  final cLon = (b.southwest.longitude + b.northeast.longitude) / 2 + shiftLon;
  final halfLat = (b.northeast.latitude - b.southwest.latitude) / 2 * factor;
  final halfLon = (b.northeast.longitude - b.southwest.longitude) / 2 * factor;
  return LatLngBounds(
    southwest: LatLng((cLat - halfLat).clamp(-85.0, 85.0), (cLon - halfLon).clamp(-180.0, 179.99999)),
    northeast: LatLng((cLat + halfLat).clamp(-85.0, 85.0), (cLon + halfLon).clamp(-180.0, 179.99999)),
  );
}

/// What to load around the map once it stops, so the next pan or zoom-in is
/// already in the cache: the visible area ×[ring] at the current zoom,
/// pushed towards where the map was moving, plus the centre at zoom+1.
/// Capped at [maxTiles]; the zoom+1 part goes first, then the ring shrinks
/// to the visible area; nothing is planned if even that is too much.
List<PrefetchPart> planPrefetch({
  required LatLngBounds visible,
  required double zoom,
  LatLng? previousCenter,
  int maxZoom = 22,
  int maxTiles = 60,
  double ring = 1.5,
}) {
  final z = zoom.floor().clamp(0, maxZoom);
  var shiftLat = 0.0;
  var shiftLon = 0.0;
  if (previousCenter != null) {
    final cLat = (visible.southwest.latitude + visible.northeast.latitude) / 2;
    final cLon = (visible.southwest.longitude + visible.northeast.longitude) / 2;
    // Half of the extra margin goes ahead of the movement.
    final spanLat = visible.northeast.latitude - visible.southwest.latitude;
    final spanLon = visible.northeast.longitude - visible.southwest.longitude;
    final dLat = cLat - previousCenter.latitude;
    final dLon = cLon - previousCenter.longitude;
    // Direction of travel in screen-sized units, made unit length.
    final uLat = spanLat > 0 ? dLat / spanLat : 0.0;
    final uLon = spanLon > 0 ? dLon / spanLon : 0.0;
    final length = math.sqrt(uLat * uLat + uLon * uLon);
    if (length > 0) {
      shiftLat = uLat / length * spanLat * (ring - 1) / 4;
      shiftLon = uLon / length * spanLon * (ring - 1) / 4;
    }
  }
  var area = _scaled(visible, ring, shiftLat: shiftLat, shiftLon: shiftLon);
  var areaTiles = tileCount(area, z);
  if (areaTiles > maxTiles) {
    area = visible;
    areaTiles = tileCount(area, z);
    if (areaTiles > maxTiles) return const [];
  }
  final parts = [PrefetchPart(area, z, areaTiles)];
  if (z + 1 <= maxZoom) {
    final centre = _scaled(visible, 0.5);
    final centreTiles = tileCount(centre, z + 1);
    if (areaTiles + centreTiles <= maxTiles) parts.add(PrefetchPart(centre, z + 1, centreTiles));
  }
  return parts;
}
