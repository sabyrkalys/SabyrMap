/// Общая обвязка тестов «Карт на экране»: каталог, карта-подделка, панель.
library;

import 'package:app/map/catalog/catalog_repository.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/map/services/google_tiles_service.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/services/offline_service.dart';
import 'package:app/map/services/yandex_tiles_service.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/map/screens/layers_panel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../services/layer_manager_test.dart' show FakeHost;
import '../../services/offline_service_test.dart' show FakeOfflineBackend;
import '../../state/map_layers_controller_test.dart' show MemoryMapStateStore;

const liberty = MapSource(
  id: 'ofm-liberty',
  name: 'OpenFreeMap Liberty',
  format: TileFormat.vector,
  storageMode: StorageMode.onlineCache,
  styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
);
const osm = MapSource(
  id: 'osm-standard',
  name: 'OSM Standard Raster',
  format: TileFormat.raster,
  storageMode: StorageMode.onlineCache,
  tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  canBeOverlay: true,
  defaultOpacity: 0.7,
);
const googleSat = MapSource(
  id: 'google-satellite',
  name: 'Google Satellite',
  format: TileFormat.raster,
  storageMode: StorageMode.onlineOnly,
  extraParams: {'mapType': 'satellite'},
);
const yHybrid = MapSource(
  id: 'yandex-hybrid',
  name: 'Яндекс Гибрид',
  format: TileFormat.raster,
  storageMode: StorageMode.onlineOnly,
  tileUrlTemplate: 'https://y/?x={x}&y={y}&z={z}&l=skl',
  canBeOverlay: true,
  defaultOpacity: 0.75,
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
  const MapProvider(id: 'osm', name: 'OpenStreetMap Maps', sources: [liberty, osm]),
  const MapProvider(id: 'google', name: 'Google Maps', isolated: true, sources: [googleSat]),
  const MapProvider(id: 'yandex', name: 'Яндекс', sources: [yHybrid, ySat]),
];

class FixedCatalog extends CatalogNotifier {
  @override
  Future<List<MapProvider>> build() async => providers;
}


const hybridLayer = ActiveLayer(sourceId: 'yandex-hybrid', type: MapLayerType.overlay, opacity: 0.75, visible: true, zIndex: 10);
const osmLayer = ActiveLayer(sourceId: 'osm-standard', type: MapLayerType.overlay, opacity: 0.7, visible: true, zIndex: 20);

MapState stateWith(List<ActiveLayer> overlays, {String base = 'ofm-liberty', List<MapPreset> presets = const []}) =>
    MapState(baseSourceId: base, overlays: overlays, favoriteIds: const [], presets: presets);

/// Карта с сохранённым [saved] и кнопка, открывающая панель (или [child]).
class LayersHarness {
  late FakeHost host;
  late ProviderContainer container;
  late MemoryMapStateStore store;

  MapState get state => container.read(mapLayersProvider);

  Future<void> pump(WidgetTester tester, {MapState? saved, Widget? child, bool open = true}) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    host = FakeHost();
    store = MemoryMapStateStore(saved);
    container = ProviderContainer(
      overrides: [
        catalogProvider.overrideWith(FixedCatalog.new),
        mapStateStoreProvider.overrideWithValue(store),
        offlineServiceProvider.overrideWithValue(OfflineService(backend: FakeOfflineBackend())),
      ],
    );
    addTearDown(container.dispose);
    await container.read(mapLayersProvider.notifier).attach(
          LayerManager(
            host: host,
            catalog: LayerCatalog(providers),
            google: GoogleTilesService(
              apiKey: 'G',
              httpClient: MockClient((r) async => r.url.path.endsWith('createSession')
                  ? http.Response('{"session":"S","expiry":"9999999999"}', 200)
                  : http.Response.bytes(const [1], 200)),
            ),
            yandex: YandexTilesService(apiKey: 'Y', httpClient: MockClient((_) async => http.Response.bytes(const [1], 200))),
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: child ??
                Builder(
                  builder: (context) => TextButton(
                    key: const Key('open_panel'),
                    onPressed: () => LayersPanel.show(context),
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (open && child == null) {
      await tester.tap(find.byKey(const Key('open_panel')));
      await tester.pumpAndSettle();
    }
  }
}
