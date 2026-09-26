import 'package:app/map/catalog/catalog_repository.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/map/screens/available_maps_screen.dart';
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
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng, LatLngBounds;

import '../services/layer_manager_test.dart' show FakeHost;
import '../services/offline_service_test.dart' show FakeOfflineBackend, status;
import '../state/map_layers_controller_test.dart' show MemoryMapStateStore;

const liberty = MapSource(
  id: 'ofm-liberty',
  name: 'OpenFreeMap Liberty',
  format: TileFormat.vector,
  storageMode: StorageMode.onlineCache,
  styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
  maxZoom: 14,
);
const googleSat = MapSource(
  id: 'google-satellite',
  name: 'Google Satellite',
  format: TileFormat.raster,
  storageMode: StorageMode.onlineOnly,
  attribution: '© Google',
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
const localMbtiles = MapSource(
  id: 'local-Карпаты.mbtiles',
  name: 'Карпаты',
  format: TileFormat.raster,
  storageMode: StorageMode.offlineRegion,
  tileUrlTemplate: 'mbtiles:///x/Карпаты.mbtiles',
  canBeOverlay: true,
);

final providers = [
  const MapProvider(id: 'osm', name: 'OpenStreetMap Maps', sources: [liberty]),
  const MapProvider(id: 'google', name: 'Google Maps', isolated: true, sources: [googleSat]),
  const MapProvider(id: 'yandex', name: 'Яндекс', sources: [yHybrid]),
  const MapProvider(id: CatalogRepository.localProviderId, name: 'Установленные карты', sources: [localMbtiles]),
];

class _FixedCatalog extends CatalogNotifier {
  @override
  Future<List<MapProvider>> build() async => providers;
}

void main() {
  late FakeHost host;
  late FakeOfflineBackend backend;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, {bool pickOverlay = false}) async {
    host = FakeHost();
    backend = FakeOfflineBackend();
    container = ProviderContainer(
      overrides: [
        catalogProvider.overrideWith(_FixedCatalog.new),
        mapStateStoreProvider.overrideWithValue(MemoryMapStateStore()),
        offlineServiceProvider.overrideWithValue(OfflineService(backend: backend)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(mapLayersProvider.notifier).attach(
          LayerManager(
            host: host,
            catalog: LayerCatalog(providers),
            google: GoogleTilesService(apiKey: '', httpClient: MockClient((_) async => http.Response('', 500))),
            yandex: YandexTilesService(apiKey: 'Y', httpClient: MockClient((_) async => http.Response.bytes(const [1], 200))),
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<bool>(builder: (_) => AvailableMapsScreen(pickOverlay: pickOverlay))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<List<String>> menuItems(WidgetTester tester, String sourceId) async {
    await tester.tap(find.byKey(Key('source_menu_$sourceId')));
    await tester.pumpAndSettle();
    final items = tester
        .widgetList<PopupMenuEntry<Object?>>(find.byWidgetPredicate((w) => w is PopupMenuItem || w is CheckedPopupMenuItem))
        .map((w) {
      final child = w is PopupMenuItem ? w.child : (w as CheckedPopupMenuItem).child;
      final enabled = w is PopupMenuItem ? w.enabled : (w as CheckedPopupMenuItem).enabled;
      return '${(child as Text).data}${enabled ? '' : ' (off)'}';
    }).toList();
    return items;
  }

  testWidgets('tabs, providers and the «Только онлайн» mark', (tester) async {
    await pump(tester);
    expect(find.text('Онлайн-карты'), findsOneWidget);
    expect(find.text('Установленные карты'), findsWidgets);
    for (final name in ['OpenStreetMap Maps', 'Google Maps', 'Яндекс']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.descendant(of: find.byKey(const Key('provider_google')), matching: find.text('Только онлайн')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('provider_yandex')), matching: find.text('Только онлайн')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('provider_osm')), matching: find.text('Только онлайн')), findsNothing);
    expect(find.text('Кэш: 0 Б'), findsOneWidget);
  });

  testWidgets('Google: no overlay, no cache clearing, no saved areas', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Google Maps'));
    await tester.pumpAndSettle();
    expect(await menuItems(tester, 'google-satellite'), ['Показать', 'Добавить как слой (off)', 'В избранное', 'Детали']);
  });

  testWidgets('OpenFreeMap: cache and «Сохранить участок карты» are offered', (tester) async {
    await pump(tester);
    await tester.tap(find.text('OpenStreetMap Maps'));
    await tester.pumpAndSettle();
    expect(await menuItems(tester, 'ofm-liberty'), [
      'Показать',
      'Добавить как слой (off)',
      'В избранное',
      'Детали',
      'Очистить кэш',
      'Сохранить участок карты',
    ]);
  });

  testWidgets('«Показать» switches the base map and returns to the map', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Яндекс'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source_yandex-hybrid')));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).baseSourceId, 'yandex-hybrid');
    expect(host.style, contains('yandex-hybrid'));
    expect(find.byType(AvailableMapsScreen), findsNothing);
  });

  testWidgets('«В избранное» toggles the star', (tester) async {
    await pump(tester);
    await tester.tap(find.text('OpenStreetMap Maps'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source_menu_ofm-liberty')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('В избранное'));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).favoriteIds, ['ofm-liberty']);
  });

  testWidgets('overlay picking: a Яндекс layer is added, Google is not selectable', (tester) async {
    await pump(tester, pickOverlay: true);
    expect(find.text('Добавить слой'), findsOneWidget);
    await tester.tap(find.text('Google Maps'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.byKey(const Key('source_google-satellite'))).enabled, isFalse);

    await tester.tap(find.text('Яндекс'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source_yandex-hybrid')));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).overlays.single.sourceId, 'yandex-hybrid');
    expect(find.byType(AvailableMapsScreen), findsNothing);
  });

  testWidgets('installed tab: local maps and saved areas with size; an area can be deleted', (tester) async {
    await pump(tester);
    // a saved area appears after the screen reloads regions
    final region = await OfflineService(backend: backend).createRegion(
      source: liberty,
      bounds: _bounds,
      minZoom: 10,
      maxZoom: 12,
      name: 'Донецк',
    );
    backend.statuses[region.id] = status(bytes: 3 * 1024 * 1024, progress: 100, complete: true);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Кэш: 3.0 МБ'), findsOneWidget);
    await tester.tap(find.text('Установленные карты').last);
    await tester.pumpAndSettle();
    expect(find.text('Карпаты'), findsOneWidget);
    expect(find.text('Донецк'), findsOneWidget);
    expect(find.text('3.0 МБ'), findsOneWidget);

    await tester.tap(find.byKey(Key('region_delete_${region.id}')));
    await tester.pumpAndSettle();
    expect(backend.regions, isEmpty);
    expect(find.text('Донецк'), findsNothing);
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 Б');
    expect(formatBytes(2048), '2 КБ');
    expect(formatBytes(3 * 1024 * 1024), '3.0 МБ');
  });
}

final _bounds = LatLngBounds(southwest: const LatLng(47.9, 37.7), northeast: const LatLng(48.1, 37.9));
