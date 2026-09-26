import 'package:app/map/models/map_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const google = MapSource(
    id: 'google-satellite',
    name: 'Google Satellite',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineOnly,
    attribution: '© Google',
    minZoom: 0,
    maxZoom: 22,
    canBeOverlay: false,
    defaultOpacity: 1.0,
    extraParams: {'mapType': 'satellite'},
  );

  test('MapSource survives a JSON round trip', () {
    final back = MapSource.fromJson(google.toJson());
    expect(back, google);
    expect(back.extraParams, {'mapType': 'satellite'});
  });

  test('MapSource.fromJson fills optional fields with defaults', () {
    final s = MapSource.fromJson({
      'id': 'ofm-liberty',
      'name': 'OpenFreeMap Liberty',
      'format': 'vector',
      'storageMode': 'onlineCache',
      'styleUrl': 'https://tiles.openfreemap.org/styles/liberty',
    });
    expect(s.minZoom, 0);
    expect(s.maxZoom, 22);
    expect(s.canBeOverlay, isFalse);
    expect(s.defaultOpacity, 1.0);
    expect(s.attribution, isNull);
    expect(s.tileUrlTemplate, isNull);
  });

  test('MapSource.fromJson rejects an unknown enum value with a clear error', () {
    expect(
      () => MapSource.fromJson({'id': 'x', 'name': 'x', 'format': 'hologram', 'storageMode': 'onlineOnly'}),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('hologram'))),
    );
  });

  test('MapProvider round trip keeps its sources and the isolated flag', () {
    const provider = MapProvider(id: 'google', name: 'Google Maps', attribution: '© Google', isolated: true, sources: [google]);
    final back = MapProvider.fromJson(provider.toJson());
    expect(back.isolated, isTrue);
    expect(back.sources, [google]);
  });

  test('ActiveLayer copyWith and round trip', () {
    const layer = ActiveLayer(sourceId: 'yandex-hybrid', type: MapLayerType.overlay, opacity: 0.75, visible: true, zIndex: 10);
    expect(ActiveLayer.fromJson(layer.toJson()), layer);
    final hidden = layer.copyWith(visible: false, opacity: 0.5);
    expect(hidden.visible, isFalse);
    expect(hidden.opacity, 0.5);
    expect(hidden.zIndex, 10);
  });

  test('MapState round trip with presets and favourites', () {
    const overlay = ActiveLayer(sourceId: 'yandex-hybrid', type: MapLayerType.overlay, opacity: 0.75, visible: true, zIndex: 10);
    const state = MapState(
      baseSourceId: 'yandex-satellite',
      overlays: [overlay],
      favoriteIds: ['ofm-liberty'],
      presets: [MapPreset(id: 'p1', name: 'Яндекс.Спутник + дороги', baseSourceId: 'yandex-satellite', overlays: [overlay])],
    );
    final back = MapState.fromJson(state.toJson());
    expect(back, state);
    expect(const MapState.initial().baseSourceId, isNull);
    expect(const MapState.initial().overlays, isEmpty);
  });
}
