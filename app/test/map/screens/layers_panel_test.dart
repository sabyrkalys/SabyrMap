import 'package:app/map/catalog/catalog_repository.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/map/screens/available_maps_screen.dart';
import 'package:app/map/screens/layers_panel.dart';
import 'package:app/map/services/google_tiles_service.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/services/offline_service.dart';
import 'package:app/map/services/yandex_tiles_service.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../services/layer_manager_test.dart' show FakeHost;
import '../services/offline_service_test.dart' show FakeOfflineBackend;
import '../state/map_layers_controller_test.dart' show MemoryMapStateStore;

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

class _FixedCatalog extends CatalogNotifier {
  @override
  Future<List<MapProvider>> build() async => providers;
}

void main() {
  late FakeHost host;
  late ProviderContainer container;
  late MemoryMapStateStore store;

  Future<void> pump(WidgetTester tester, {MapState? saved}) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    host = FakeHost();
    store = MemoryMapStateStore(saved);
    container = ProviderContainer(
      overrides: [
        catalogProvider.overrideWith(_FixedCatalog.new),
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
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: LayersPanel())));
    await tester.pumpAndSettle();
  }

  MapState stateWith(List<ActiveLayer> overlays) =>
      MapState(baseSourceId: 'ofm-liberty', overlays: overlays, favoriteIds: const [], presets: const []);
  const hybridLayer = ActiveLayer(sourceId: 'yandex-hybrid', type: MapLayerType.overlay, opacity: 0.75, visible: true, zIndex: 10);
  const osmLayer = ActiveLayer(sourceId: 'osm-standard', type: MapLayerType.overlay, opacity: 0.7, visible: true, zIndex: 20);

  testWidgets('sections: base, overlays with a load indicator, presets', (tester) async {
    await pump(tester, saved: stateWith(const [hybridLayer]));
    expect(find.text('Базовая подложка'), findsOneWidget);
    expect(find.text('Наложенные слои (1/3)'), findsOneWidget);
    expect(find.text('Пресеты'), findsOneWidget);
    expect(find.text('+ Добавить слой'), findsOneWidget);
    expect(tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>)).groupValue, 'ofm-liberty');
  });

  testWidgets('picking a base radio switches the map', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('base_yandex-sat')));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).baseSourceId, 'yandex-sat');
    expect(host.style, contains('yandex-sat'));
  });

  testWidgets('overlay row: visibility, opacity slider in %, delete', (tester) async {
    await pump(tester, saved: stateWith(const [hybridLayer]));
    expect(find.text('Яндекс Гибрид'), findsWidgets);
    expect(find.text('75%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('overlay_visible_yandex-hybrid')));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).overlays.single.visible, isFalse);

    tester.widget<Slider>(find.byKey(const Key('overlay_opacity_yandex-hybrid'))).onChangeEnd!(0.3);
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).overlays.single.opacity, 0.3);
    expect(find.text('30%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('overlay_delete_yandex-hybrid')));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).overlays, isEmpty);
  });

  testWidgets('reordering the list reorders the layers (top of the list = top of the map)', (tester) async {
    await pump(tester, saved: stateWith(const [hybridLayer, osmLayer]));
    final list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    // Shown top → bottom: OSM (z20) first, Hybrid (z10) second. Move Hybrid to the top.
    list.onReorder(1, 0);
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).overlays.map((l) => l.sourceId), ['osm-standard', 'yandex-hybrid']);
  });

  testWidgets('«+ Добавить слой» opens the catalog in overlay-picking mode', (tester) async {
    await pump(tester);
    await tester.tap(find.text('+ Добавить слой'));
    await tester.pumpAndSettle();
    expect(find.byType(AvailableMapsScreen), findsOneWidget);
    expect(find.text('Добавить слой'), findsOneWidget);
  });

  testWidgets('over a Google base, adding is refused with the reason', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('base_google-satellite')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Добавить слой'));
    await tester.pumpAndSettle();
    expect(find.byType(AvailableMapsScreen), findsNothing);
    expect(find.text(LayerManager.isolatedMessage), findsOneWidget);
  });

  testWidgets('a preset is applied with one tap', (tester) async {
    const preset = MapPreset(id: 'p', name: 'Спутник + гибрид', baseSourceId: 'yandex-sat', overlays: [hybridLayer]);
    await pump(tester, saved: const MapState(baseSourceId: null, overlays: [], favoriteIds: [], presets: [preset]));
    await tester.tap(find.text('Спутник + гибрид'));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).baseSourceId, 'yandex-sat');
    expect(container.read(mapLayersProvider).overlays.single.sourceId, 'yandex-hybrid');
  });
}
