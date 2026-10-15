import 'dart:convert';

import 'package:app/map/services/maplibre_layer_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  test('a decoded style source passes maplibre_gl fromJson casts', () {
    final source = jsonDecode(
      '{"type":"vector","tiles":["https://h/tiles/roads/{z}/{x}/{y}"],"bounds":[22,43.6,41.5,52],"minzoom":0,"maxzoom":17}',
    ) as Map<String, dynamic>;

    final json = MapLibreLayerHost.typedSourceJson(source);
    final vector = VectorSourceProperties.fromJson(json);
    final raster = RasterSourceProperties.fromJson({...json, 'type': 'raster'});

    expect(vector.tiles, ['https://h/tiles/roads/{z}/{x}/{y}']);
    expect(vector.bounds, [22.0, 43.6, 41.5, 52.0]);
    expect(raster.tiles, ['https://h/tiles/roads/{z}/{x}/{y}']);
    expect(json['maxzoom'], 17);
  });
}
