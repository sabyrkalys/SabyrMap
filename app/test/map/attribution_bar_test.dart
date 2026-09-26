import 'package:app/map/attribution_bar.dart';
import 'package:app/map/models/map_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attributions of base and visible overlays, without repeats', () {
    const base = MapSource(
      id: 'ofm-liberty',
      name: 'Liberty',
      format: TileFormat.vector,
      storageMode: StorageMode.onlineCache,
      attribution: '© OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors',
    );
    const osm = MapSource(
      id: 'osm',
      name: 'OSM',
      format: TileFormat.raster,
      storageMode: StorageMode.onlineCache,
      attribution: '© OpenStreetMap contributors',
    );
    expect(attributionText(base, const [osm]), '© OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors');
    expect(attributionText(null, const []), '');
  });
}
