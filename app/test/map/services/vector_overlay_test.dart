import 'package:app/map/services/vector_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

/// Похоже на hybrid-day: фон, спутник, здания, дороги, подписи.
final hybridStyle = <String, dynamic>{
  'version': 8,
  'sources': {
    'osm': {
      'type': 'vector',
      'tiles': ['https://t/osm/{z}/{x}/{y}'],
      'maxzoom': 14,
    },
    'satellite': {
      'type': 'raster',
      'tiles': ['https://t/satellite/{z}/{x}/{y}'],
    },
  },
  'layers': [
    {'id': 'background', 'type': 'background'},
    {'id': 'satellite', 'type': 'raster', 'source': 'satellite'},
    {
      'id': 'building',
      'type': 'fill',
      'source': 'osm',
      'source-layer': 'building',
      'paint': {'fill-opacity': 0.5},
    },
    {
      'id': 'road-main',
      'type': 'line',
      'source': 'osm',
      'source-layer': 'transportation',
      'paint': {
        'line-opacity': ['interpolate', ['linear'], ['zoom'], 8, 0.4, 14, 1],
      },
    },
    {
      'id': 'place-label',
      'type': 'symbol',
      'source': 'osm',
      'source-layer': 'place',
      'layout': {'text-field': '{name}'},
    },
  ],
};

void main() {
  test('takes the drawable vector layers, prefixed; background and imagery stay behind', () {
    final overlay = VectorOverlay.fromStyle('roads', hybridStyle);
    expect(overlay.layers.map((l) => l['id']), ['roads~building', 'roads~road-main', 'roads~place-label']);
    expect(overlay.layers.map((l) => l['source']).toSet(), {'roads~osm'});
    expect(overlay.layers[1]['source-layer'], 'transportation');
    expect(overlay.sources.keys, ['roads~osm']);
    expect(overlay.bottomLayerId, 'roads~building');
  });

  test('opacity scales numbers, zoom curves and missing values', () {
    final overlay = VectorOverlay.fromStyle('roads', hybridStyle);
    final half = [for (final l in overlay.layers) VectorOverlay.withOpacity(l, 0.5)];
    expect((half[0]['paint'] as Map)['fill-opacity'], 0.25);
    expect((half[1]['paint'] as Map)['line-opacity'], ['interpolate', ['linear'], ['zoom'], 8, 0.2, 14, 0.5]);
    expect((half[2]['paint'] as Map)['text-opacity'], 0.5);
    expect((half[2]['paint'] as Map)['icon-opacity'], 0.5);
    expect(VectorOverlay.scaleOpacity(['step', ['zoom'], 0, 10, 1], 0.5), ['step', ['zoom'], 0, 10, 0.5]);
    expect(VectorOverlay.scaleOpacity(['get', 'o'], 0.5), ['*', ['get', 'o'], 0.5]);
  });
}
