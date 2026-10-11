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
  id: 'ortho-Доброполье.mbtiles',
  name: 'Доброполье',
  format: TileFormat.raster,
  storageMode: StorageMode.offlineRegion,
  tileUrlTemplate: 'mbtiles:///orthophoto/Доброполье.mbtiles',
  canBeOverlay: true,
);
const ortho2 = MapSource(
  id: 'ortho-Авдеевка 2026.mbtiles',
  name: 'Авдеевка 2026',
  format: TileFormat.raster,
  storageMode: StorageMode.offlineRegion,
  tileUrlTemplate: 'mbtiles:///orthophoto/Авдеевка 2026.mbtiles',
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

List<MapProvider> catalogWith(List<MapSource> orthophotos) => [
  const MapProvider(id: 'osm', name: 'OSM', sources: [base]),
  const MapProvider(id: CatalogRepository.localProviderId, name: 'Установленные карты', sources: [otherLocal]),
  if (orthophotos.isNotEmpty)
    MapProvider(id: CatalogRepository.orthophotoProviderId, name: 'Ортофотопланы', sources: orthophotos),
];

class _FixedCatalog extends CatalogNotifier {
  _FixedCatalog(this.providers);

  final List<MapProvider> providers;

  @override
  Future<List<MapProvider>> build() async => providers;
}

void main() {
  group('isOrthophoto', () {
    test('any file of the orthophoto folder, whatever its name', () {
      expect(isOrthophoto(ortho), isTrue);
      expect(isOrthophoto(ortho2), isTrue);
      expect(isOrthophoto(otherLocal), isFalse);
      expect(isOrthophoto(base), isFalse);
      const namedLikeOne = MapSource(
        id: 'local-ортофотоплан.mbtiles',
        name: 'ортофотоплан',
        format: TileFormat.raster,
        storageMode: StorageMode.offlineRegion,
      );
      expect(isOrthophoto(namedLikeOne), isFalse);
    });

    test('orthophotosOf lists them by name', () {
      expect(orthophotosOf(catalogWith([ortho, ortho2])).map((s) => s.name), ['Авдеевка 2026', 'Доброполье']);
    });
  });

  group('OrthophotoSheet', () {
    late ProviderContainer container;

    Future<void> pump(WidgetTester tester, List<MapSource> orthophotos) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final providers = catalogWith(orthophotos);
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
      await pump(tester, [ortho, ortho2]);
      expect(find.text('Ортофотопланы'), findsOneWidget);
      expect(find.text('Доброполье'), findsOneWidget);
      expect(find.text('Авдеевка 2026'), findsOneWidget);
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
      expect(find.text('«Доброполье» добавлен как слой'), findsOneWidget);
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

    testWidgets('no orthophotos: an explanation, the switch is off', (tester) async {
      await pump(tester, const []);
      expect(find.byKey(const Key('orthophoto_empty')), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('orthophoto_all'))).onChanged, isNull);
    });

    testWidgets('«Показывать все» shows every territory at once and is remembered', (tester) async {
      await pump(tester, [ortho, ortho2]);
      expect(find.text('Территорий: 2 — каждая там, где есть снимок'), findsOneWidget);
      await tester.tap(find.byKey(const Key('orthophoto_all')));
      await tester.pumpAndSettle();
      final state = container.read(mapLayersProvider);
      expect(state.orthophotosOn, isTrue);
      expect(state.overlays, isEmpty);
      expect(state.baseSourceId, base.id);
      expect(find.text('283.9 МБ · показан'), findsOneWidget);

      await tester.tap(find.byKey(const Key('orthophoto_all')));
      await tester.pumpAndSettle();
      expect(container.read(mapLayersProvider).orthophotosOn, isFalse);
    });
  });
}
