import 'dart:convert';

import 'package:app/map/catalog/catalog_repository.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/map/services/google_tiles_service.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/services/yandex_tiles_service.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../services/layer_manager_test.dart' show FakeHost;

class MemoryMapStateStore implements MapStateStore {
  MemoryMapStateStore([this.saved]);

  MapState? saved;

  @override
  Future<MapState?> load() async => saved;

  @override
  Future<void> save(MapState state) async => saved = state;
}

void main() {
  const liberty = MapSource(
    id: 'ofm-liberty',
    name: 'OpenFreeMap Liberty',
    format: TileFormat.vector,
    storageMode: StorageMode.onlineCache,
    styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
  );
  const osm = MapSource(
    id: 'osm-standard',
    name: 'OSM',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineCache,
    tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    canBeOverlay: true,
    defaultOpacity: 0.7,
  );
  const ySat = MapSource(
    id: 'yandex-sat',
    name: 'Яндекс Спутник',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineOnly,
    tileUrlTemplate: 'https://y/?x={x}&y={y}&z={z}&l=sat',
    canBeOverlay: true,
    defaultOpacity: 0.75,
  );
  final providers = [
    const MapProvider(id: 'osm', name: 'OSM', sources: [liberty, osm]),
    const MapProvider(id: 'yandex', name: 'Яндекс', sources: [ySat]),
  ];

  late FakeHost host;
  late int yandexStatus;

  LayerManager manager() {
    host = FakeHost();
    return LayerManager(
      host: host,
      catalog: LayerCatalog(providers),
      google: GoogleTilesService(apiKey: '', httpClient: MockClient((_) async => http.Response('', 500))),
      yandex: YandexTilesService(apiKey: 'Y', httpClient: MockClient((_) async => http.Response.bytes(const [1], yandexStatus))),
    );
  }

  ProviderContainer container(MemoryMapStateStore store) {
    final c = ProviderContainer(
      overrides: [
        mapStateStoreProvider.overrideWithValue(store),
        catalogProvider.overrideWith(() => _FixedCatalog(providers)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => yandexStatus = 200);

  test('before a map is attached, changes report that the map is not ready', () async {
    final c = container(MemoryMapStateStore());
    await expectLater(
      c.read(mapLayersProvider.notifier).setBase(liberty),
      throwsA(isA<LayerException>().having((e) => e.message, 'message', 'Карта ещё не готова')),
    );
  });

  test('attach applies the saved base and overlays (app restart)', () async {
    final saved = MapState(
      baseSourceId: 'yandex-sat',
      overlays: const [ActiveLayer(sourceId: 'osm-standard', type: MapLayerType.overlay, opacity: 0.5, visible: true, zIndex: 10)],
      favoriteIds: const ['ofm-liberty'],
      presets: const [],
    );
    final c = container(MemoryMapStateStore(saved));
    final result = await c.read(mapLayersProvider.notifier).attach(manager());

    expect(result.ok, isTrue);
    expect(host.style, contains('yandex-sat'));
    expect(host.layers, ['osm-standard-layer']);
    expect(c.read(mapLayersProvider).favoriteIds, ['ofm-liberty']);
    expect(c.read(mapLayersProvider).overlays.single.opacity, 0.5);
  });

  test('attach with nothing saved leaves the current map alone', () async {
    final c = container(MemoryMapStateStore());
    await c.read(mapLayersProvider.notifier).attach(manager());
    expect(host.calls, isEmpty);
    expect(c.read(mapLayersProvider).baseSourceId, isNull);
  });

  test('changes go through the manager, update the state and are saved', () async {
    final store = MemoryMapStateStore();
    final c = container(store);
    final notifier = c.read(mapLayersProvider.notifier);
    await notifier.attach(manager());

    await notifier.setBase(liberty);
    await notifier.addOverlay(osm);
    await notifier.addOverlay(ySat, opacity: 0.4);
    await notifier.setOpacity('osm-standard', 0.2);
    await notifier.setVisibility('yandex-sat', false);
    await notifier.reorderOverlays(['yandex-sat', 'osm-standard']);
    await notifier.toggleFavorite('ofm-liberty');

    final state = c.read(mapLayersProvider);
    expect(state.baseSourceId, 'ofm-liberty');
    expect(state.overlays.map((l) => (l.sourceId, l.opacity, l.visible, l.zIndex)), [
      ('yandex-sat', 0.4, false, 10),
      ('osm-standard', 0.2, true, 20),
    ]);
    expect(state.favoriteIds, ['ofm-liberty']);
    expect(store.saved, state);

    await notifier.removeOverlay('yandex-sat');
    await notifier.toggleFavorite('ofm-liberty');
    expect(c.read(mapLayersProvider).overlays.map((l) => l.sourceId), ['osm-standard']);
    expect(c.read(mapLayersProvider).favoriteIds, isEmpty);
  });

  test('a refused change leaves the state as it was', () async {
    final c = container(MemoryMapStateStore());
    final notifier = c.read(mapLayersProvider.notifier);
    await notifier.attach(manager());
    await notifier.setBase(liberty);
    yandexStatus = 403;
    await expectLater(notifier.addOverlay(ySat), throwsA(isA<LayerException>()));
    expect(c.read(mapLayersProvider).overlays, isEmpty);
  });

  test('presets: apply switches base and overlays; save stores the current stack', () async {
    final c = container(MemoryMapStateStore());
    final notifier = c.read(mapLayersProvider.notifier);
    await notifier.attach(manager());

    const preset = MapPreset(
      id: 'p',
      name: 'Спутник + OSM',
      baseSourceId: 'yandex-sat',
      overlays: [ActiveLayer(sourceId: 'osm-standard', type: MapLayerType.overlay, opacity: 0.6, visible: true, zIndex: 10)],
    );
    final result = await notifier.applyPreset(preset);
    expect(result.ok, isTrue);
    expect(c.read(mapLayersProvider).baseSourceId, 'yandex-sat');
    expect(host.layers, ['osm-standard-layer']);
    expect(host.opacities['osm-standard-layer'], 0.6);

    await notifier.savePreset('Мой набор');
    final saved = c.read(mapLayersProvider).presets.last;
    expect(saved.name, 'Мой набор');
    expect(saved.baseSourceId, 'yandex-sat');
    expect(saved.overlays.single.sourceId, 'osm-standard');
    await notifier.deletePreset(saved.id);
    expect(c.read(mapLayersProvider).presets.where((p) => p.name == 'Мой набор'), isEmpty);
  });

  test('SecureMapStateStore round trip', () async {
    // covered by MapState JSON tests; here only the key is checked
    expect(SecureMapStateStore.storageKey, 'map_state');
    expect(jsonEncode(const MapState.initial().toJson()), isNotEmpty);
  });
}

class _FixedCatalog extends CatalogNotifier {
  _FixedCatalog(this._providers);

  final List<MapProvider> _providers;

  @override
  Future<List<MapProvider>> build() async => _providers;
}
