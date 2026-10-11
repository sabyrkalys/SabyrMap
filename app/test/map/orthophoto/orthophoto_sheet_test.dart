import 'package:app/map/catalog/catalog_repository.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/map/orthophoto/orthophoto_sheet.dart';
import 'package:app/map/services/google_tiles_service.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/services/yandex_tiles_service.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../services/layer_manager_test.dart' show FakeHost;
import '../state/map_layers_controller_test.dart' show MemoryMapStateStore;

const base = MapSource(
  id: 'osm',
  name: 'OSM',
  format: TileFormat.raster,
  storageMode: StorageMode.onlineCache,
  tileUrlTemplate: 'https://t/{z}/{x}/{y}.png',
);
const ortho = MapSource(
  id: 'local-Ортофотоплан Доброполье.mbtiles',
  name: 'Ортофотоплан Доброполье',
  format: TileFormat.raster,
  storageMode: StorageMode.offlineRegion,
  tileUrlTemplate: 'mbtiles:///maps/Ортофотоплан Доброполье.mbtiles',
  canBeOverlay: true,
);
const otherLocal = MapSource(
  id: 'local-Карпаты.mbtiles',
  name: 'Карпаты',
  format: TileFormat.raster,
  storageMode: StorageMode.offlineRegion,
  tileUrlTemplate: 'mbtiles:///maps/Карпаты.mbtiles',
  canBeOverlay: true,
);

List<MapProvider> catalogWith(List<MapSource> local) => [
  const MapProvider(id: 'osm', name: 'OSM', sources: [base]),
  MapProvider(id: CatalogRepository.localProviderId, name: 'Установленные карты', sources: local),
];

class _FixedCatalog extends CatalogNotifier {
  _FixedCatalog(this.providers);

  final List<MapProvider> providers;

  @override
  Future<List<MapProvider>> build() async => providers;
}

void main() {
  group('isOrthophoto', () {
    test('only local raster maps with «ортофото» in the name', () {
      expect(isOrthophoto(ortho), isTrue);
      expect(isOrthophoto(otherLocal), isFalse);
      expect(isOrthophoto(base), isFalse);
      const online = MapSource(
        id: 'server-orthophoto',
        name: 'Ортофото сервера',
        format: TileFormat.raster,
        storageMode: StorageMode.onlineCache,
      );
      expect(isOrthophoto(online), isFalse);
    });

    test('orthophotosOf lists them by name', () {
      const second = MapSource(
        id: 'local-ортофото Авдеевка.mbtiles',
        name: 'ортофото Авдеевка',
        format: TileFormat.raster,
        storageMode: StorageMode.offlineRegion,
      );
      expect(orthophotosOf(catalogWith([ortho, otherLocal, second])).map((s) => s.name), [
        'ортофото Авдеевка',
        'Ортофотоплан Доброполье',
      ]);
    });
  });

  group('OrthophotoSheet', () {
    late ProviderContainer container;

    Future<void> pump(WidgetTester tester, List<MapSource> local) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final providers = catalogWith(local);
      container = ProviderContainer(
        overrides: [
          catalogProvider.overrideWith(() => _FixedCatalog(providers)),
          mapStateStoreProvider.overrideWithValue(MemoryMapStateStore()),
          localMapInfoProvider.overrideWith(
            (ref) async => {ortho.id: const LocalMapInfo(sizeBytes: 297656320)},
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(mapLayersProvider.notifier).attach(
        LayerManager(
          host: FakeHost(),
          catalog: LayerCatalog(providers),
          google: GoogleTilesService(apiKey: '', httpClient: MockClient((_) async => http.Response('', 500))),
          yandex: YandexTilesService(apiKey: '', httpClient: MockClient((_) async => http.Response('', 500))),
        ),
      );
      await container.read(mapLayersProvider.notifier).setBase(base);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(onPressed: () => showOrthophotoSheet(context), child: const Text('open')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(Key('orthophoto_${ortho.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('map_card_menu')), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const Key('map_card_menu')), matching: find.text(label)));
      await tester.pumpAndSettle();
    }

    testWidgets('lists only orthophotos, with their size', (tester) async {
      await pump(tester, [ortho, otherLocal]);
      expect(find.text('Ортофотопланы'), findsOneWidget);
      expect(find.text('Ортофотоплан Доброполье'), findsOneWidget);
      expect(find.text('Карпаты'), findsNothing);
      expect(find.text('283.9 МБ'), findsOneWidget);
    });

    testWidgets('«Добавить как слой» puts it over the map and closes the sheet', (tester) async {
      await pump(tester, [ortho]);
      await pick(tester, 'Добавить как слой');
      final state = container.read(mapLayersProvider);
      expect(state.overlays.map((l) => l.sourceId), [ortho.id]);
      expect(state.baseSourceId, base.id);
      expect(find.byKey(const Key('orthophoto_sheet')), findsNothing);
      expect(find.text('«Ортофотоплан Доброполье» добавлен как слой'), findsOneWidget);
    });

    testWidgets('«Показать» makes it the base map', (tester) async {
      await pump(tester, [ortho]);
      await pick(tester, 'Показать');
      expect(container.read(mapLayersProvider).baseSourceId, ortho.id);
      expect(find.byKey(const Key('orthophoto_sheet')), findsNothing);
    });

    testWidgets('an orthophoto on screen offers «Убрать»', (tester) async {
      await pump(tester, [ortho]);
      await pick(tester, 'Добавить как слой');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('283.9 МБ · слой'), findsOneWidget);
      await pick(tester, 'Убрать');
      expect(container.read(mapLayersProvider).overlays, isEmpty);
    });

    testWidgets('no orthophotos: an explanation', (tester) async {
      await pump(tester, [otherLocal]);
      expect(find.byKey(const Key('orthophoto_empty')), findsOneWidget);
    });
  });
}
