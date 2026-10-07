import 'package:app/map/catalog/catalog_repository.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/map/regions/server_region_service.dart' show StorageInfo;
import 'package:app/map/screens/available_maps/available_maps_models.dart';
import 'package:app/map/screens/available_maps/device_storage.dart';
import 'package:app/mediafile/mediafile_folder_service.dart';
import 'package:file/memory.dart';
import 'package:app/map/screens/available_maps/map_card.dart';
import 'package:app/map/screens/available_maps/maps_app_bar.dart';
import 'package:app/map/screens/available_maps_screen.dart';
import 'package:app/map/services/google_tiles_service.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/services/map_previews.dart';
import 'package:app/map/services/offline_service.dart';
import 'package:app/map/services/tile_cache_stats.dart';
import 'package:app/map/services/yandex_tiles_service.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'dart:io';
import 'dart:typed_data';

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

  Future<void> pump(
    WidgetTester tester, {
    bool pickOverlay = false,
    Map<String, LocalMapInfo> localInfo = const {},
    TileCacheReader cache = const _Cache({}),
    StorageUsage? storage = const StorageUsage(path: '/sd/maps', usedBytes: 238 * _gib, totalBytes: 487 * _gib),
    Map<String, File> previews = const {},
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    host = FakeHost();
    backend = FakeOfflineBackend();
    container = ProviderContainer(
      overrides: [
        catalogProvider.overrideWith(_FixedCatalog.new),
        mapStateStoreProvider.overrideWithValue(MemoryMapStateStore()),
        offlineServiceProvider.overrideWithValue(OfflineService(backend: backend)),
        localMapInfoProvider.overrideWith((ref) async => localInfo),
        deviceStorageProvider.overrideWith((ref) async => storage),
        tileCacheReaderProvider.overrideWithValue(cache),
        mapPreviewProvider.overrideWith((ref, source) async => previews[source.id]),
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
    final items = find.descendant(
      of: find.byKey(const Key('map_card_menu')),
      matching: find.byWidgetPredicate(
        (w) => w is InkWell && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('map_card_menu_'),
      ),
    );
    return [
      for (final element in items.evaluate())
        '${tester.widget<Text>(find.descendant(of: find.byWidget(element.widget), matching: find.byType(Text))).data}'
            '${(element.widget as InkWell).onTap == null ? ' (off)' : ''}',
    ];
  }

  Future<void> toggle(WidgetTester tester, String groupId) async {
    await tester.tap(find.byKey(Key('group_header_$groupId')));
    await tester.pumpAndSettle();
  }

  Finder inGroup(String groupId, Finder finder) =>
      find.descendant(of: find.byKey(Key('group_$groupId')), matching: finder);

  testWidgets('two titles, one list of groups, no tabs; «Только онлайн» on online-only groups', (tester) async {
    await pump(tester);
    expect(find.byType(TabBar), findsNothing);
    expect(find.descendant(of: find.byType(MapsAppBar), matching: find.text('Онлайн-карты')), findsOneWidget);
    expect(find.descendant(of: find.byType(MapsAppBar), matching: find.text('Установленные карты')), findsOneWidget);
    for (final title in ['OPENSTREETMAP', 'GOOGLE MAPS', 'ЯНДЕКС', 'СВОИ КАРТЫ']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(inGroup('google', find.text('Только онлайн')), findsOneWidget);
    expect(inGroup('yandex', find.text('Только онлайн')), findsOneWidget);
    expect(inGroup('osm', find.text('Только онлайн')), findsNothing);
    expect(find.text('Кэш: 0 Б'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('cache_indicator')), matching: find.text('238 ГБ / 487 ГБ')),
        findsOneWidget);
  });

  testWidgets('a card shows the map\'s preview once it is drawn', (tester) async {
    await pump(tester, previews: {'google-satellite': File('/previews/google.jpg')});

    final image = tester.widget<Image>(
      find.descendant(of: find.byKey(const Key('source_google-satellite')), matching: find.byType(Image)),
    );
    expect((image.image as FileImage).file.path, '/previews/google.jpg');
  });

  testWidgets('MapCard: a placeholder until the preview is there', (tester) async {
    Widget card(ImageProvider? thumbnail) => MaterialApp(
          home: Scaffold(
            body: MapCard(name: 'Спутник', caption: 'Нет', kind: MapKind.satellite, thumbnail: thumbnail),
          ),
        );
    await tester.pumpWidget(card(null));
    expect(find.byType(Image), findsNothing);

    await tester.pumpWidget(card(MemoryImage(_png)));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the storage bar shows no numbers while the volume size is unknown', (tester) async {
    await pump(tester, storage: null);
    expect(find.textContaining('ГБ /'), findsNothing);
    expect(find.text('Кэш: 0 Б'), findsOneWidget);
  });

  test('readDeviceStorage: used = total − free of the volume with the maps folder; null when unknown', () async {
    final folder = MediaFileFolderService(subfolder: 'maps', fileSystem: MemoryFileSystem(), baseDirectoryPath: '/sd');
    final usage = await readDeviceStorage(folder, const _Storage(free: 249 * _gib, total: 487 * _gib));
    expect(usage!.label, '238 ГБ / 487 ГБ');
    expect(usage.path, '/sd');
    expect(await readDeviceStorage(folder, const _Storage(free: 1, total: null)), isNull);
  });

  testWidgets('groups open independently; Google Maps starts open', (tester) async {
    await pump(tester);
    expect(find.text('Google Satellite'), findsOneWidget);
    expect(find.text('OpenFreeMap Liberty'), findsNothing);

    await toggle(tester, 'osm');
    expect(find.text('OpenFreeMap Liberty'), findsOneWidget);
    expect(find.text('Google Satellite'), findsOneWidget);

    await toggle(tester, 'google');
    expect(find.text('Google Satellite'), findsNothing);
    expect(find.text('OpenFreeMap Liberty'), findsOneWidget);
  });

  testWidgets('Google: no overlay, no cache clearing, no saved areas', (tester) async {
    await pump(tester);
    expect(await menuItems(tester, 'google-satellite'), [
      'Показать',
      'Добавить как слой (off)',
      'Сохранить в избранные',
      'Детали',
    ]);
    expect(find.text('Google Satellite'), findsNWidgets(2)); // the card and the menu's title
    await tester.tap(find.byKey(const Key('map_card_menu_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('map_card_menu')), findsNothing);
  });

  testWidgets('a map on screen offers «Убрать» instead of «Показать» / «Добавить как слой»', (tester) async {
    await pump(tester);
    await container.read(mapLayersProvider.notifier).addOverlay(yHybrid);
    await toggle(tester, 'yandex');
    expect(await menuItems(tester, 'yandex-hybrid'), ['Убрать', 'Сохранить в избранные', 'Детали']);

    await tester.tap(find.byKey(const Key('map_card_menu_remove')));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).overlays, isEmpty);
    expect(find.text('«Яндекс Гибрид» убрана с экрана'), findsOneWidget);
  });

  testWidgets('a tap outside the menu closes it', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('source_menu_google-satellite')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('map_card_menu')), findsNothing);
  });

  testWidgets('a tap on a card switches the base map and returns to the map', (tester) async {
    await pump(tester);
    await toggle(tester, 'yandex');
    await tester.tap(find.byKey(const Key('source_yandex-hybrid')));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).baseSourceId, 'yandex-hybrid');
    expect(host.style, contains('yandex-hybrid'));
    expect(find.byType(AvailableMapsScreen), findsNothing);
  });

  testWidgets('«Сохранить в избранные» toggles the star', (tester) async {
    await pump(tester);
    await toggle(tester, 'osm');
    await tester.tap(find.byKey(const Key('source_menu_ofm-liberty')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('map_card_menu_favorite')));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).favoriteIds, ['ofm-liberty']);
    expect(find.text('«OpenFreeMap Liberty» сохранена в избранные'), findsOneWidget);
    expect(tester.widget<MapCard>(find.byKey(const Key('source_ofm-liberty'))).favorite, isTrue);
  });

  testWidgets('overlay picking: a Яндекс layer is added, Google is not selectable', (tester) async {
    await pump(tester, pickOverlay: true);
    expect(find.text('Добавить слой'), findsOneWidget);
    expect(find.byKey(const Key('add_map_button')), findsNothing);
    expect(tester.widget<MapCard>(find.byKey(const Key('source_google-satellite'))).enabled, isFalse);

    await toggle(tester, 'yandex');
    await tester.tap(find.byKey(const Key('source_yandex-hybrid')));
    await tester.pumpAndSettle();
    expect(container.read(mapLayersProvider).overlays.single.sourceId, 'yandex-hybrid');
    expect(find.byType(AvailableMapsScreen), findsNothing);
  });

  testWidgets('a saved area sits under its source group with its size; it can be deleted', (tester) async {
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
    await tester.tap(find.byKey(const Key('maps_close_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Кэш: 3.0 МБ'), findsOneWidget);
    expect(inGroup('osm', find.text('скачано 3.0 МБ')), findsOneWidget); // the group's subtitle
    await toggle(tester, 'osm');
    expect(inGroup('osm', find.byKey(const Key('downloaded_label_osm'))), findsOneWidget);
    expect(inGroup('osm', find.byKey(Key('region_${region.id}'))), findsOneWidget);
    expect(find.descendant(of: find.byKey(Key('region_${region.id}')), matching: find.text('3.0 МБ')), findsOneWidget);

    await tester.tap(find.byKey(Key('region_delete_${region.id}')));
    await tester.pumpAndSettle();
    expect(backend.regions, isEmpty);
    expect(find.text('Донецк'), findsNothing);
  });

  testWidgets('«Очистить кэш» deletes the saved areas of a map after a confirmation', (tester) async {
    await pump(tester);
    final region = await OfflineService(backend: backend).createRegion(
      source: liberty,
      bounds: _bounds,
      minZoom: 10,
      maxZoom: 12,
      name: 'Донецк',
    );
    backend.statuses[region.id] = status(bytes: 3 * 1024 * 1024, progress: 100, complete: true);
    await tester.tap(find.byKey(const Key('maps_close_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await toggle(tester, 'osm');

    expect(await menuItems(tester, 'ofm-liberty'), [
      'Показать',
      'Добавить как слой (off)',
      'Сохранить в избранные',
      'Детали',
      'Очистить кэш',
    ]);
    await tester.tap(find.byKey(const Key('map_card_menu_clearCache')));
    await tester.pumpAndSettle();
    expect(find.text('Удалить сохранённые участки карты «OpenFreeMap Liberty» (3.0 МБ)?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clear_cache_confirm')));
    await tester.pumpAndSettle();
    expect(backend.regions, isEmpty);
    expect(find.text('Кэш очищен'), findsOneWidget);
  });

  testWidgets('«Детали» shows source, size, date, coverage and tile format', (tester) async {
    await pump(
      tester,
      localInfo: {
        'local-Карпаты.mbtiles': LocalMapInfo(
          sizeBytes: 5 * 1024 * 1024,
          originSourceId: 'ofm-liberty',
          createdAt: DateTime(2026, 10, 7, 12),
          bbox: const [37.7, 47.9, 37.9, 48.1],
          maxZoom: 12,
        ),
      },
    );
    await toggle(tester, 'osm');
    await tester.tap(find.byKey(const Key('source_menu_local-Карпаты.mbtiles')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('map_card_menu_details')));
    await tester.pumpAndSettle();
    expect(find.text('OPENSTREETMAP'), findsWidgets);
    expect(find.text('5.0 МБ'), findsWidgets);
    expect(find.text('07.10.2026'), findsOneWidget);
    expect(find.text('47.900…48.100 с. ш., 37.700…37.900 в. д., масштаб 0–12'), findsOneWidget);
    expect(find.text('Растровые · 📦 Офлайн'), findsOneWidget);
    expect(find.textContaining('mbtiles://'), findsNothing);
    expect(find.text('URL'), findsNothing);
  });

  testWidgets('installed maps show their disk size; unknown origin goes to «Свои карты»', (tester) async {
    await pump(tester, localInfo: const {'local-Карпаты.mbtiles': LocalMapInfo(sizeBytes: 5 * 1024 * 1024)});
    await toggle(tester, ownGroupId);
    expect(inGroup(ownGroupId, find.text('Карпаты')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('source_local-Карпаты.mbtiles')), matching: find.text('5.0 МБ')),
        findsOneWidget);
  });

  testWidgets('a map downloaded from a catalog map is listed under that map\'s group', (tester) async {
    await pump(
      tester,
      localInfo: const {
        'local-Карпаты.mbtiles': LocalMapInfo(sizeBytes: 5 * 1024 * 1024, originSourceId: 'ofm-liberty'),
      },
    );
    expect(find.text('СВОИ КАРТЫ'), findsNothing);
    expect(inGroup('osm', find.text('скачано 5.0 МБ')), findsOneWidget); // the group's subtitle
    await toggle(tester, 'osm');
    expect(inGroup('osm', find.text('Карпаты')), findsOneWidget);
    expect(inGroup('osm', find.text('Скачанные'.toUpperCase())), findsOneWidget);
  });

  testWidgets('online maps show what MapLibre\'s tile cache holds for them', (tester) async {
    await pump(
      tester,
      cache: const _Cache(
        {'https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf': 3 * _mib, 'https://y/?x={x}&y={y}&z={z}&l=skl': _mib},
        resources: {
          'https://tiles.openfreemap.org/styles/liberty': '{"version": 8, "sources": {"ofm": {"type": "vector", '
              '"url": "https://tiles.openfreemap.org/planet"}}, "layers": []}',
          'https://tiles.openfreemap.org/planet': '{"tiles": ["https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf"]}',
        },
      ),
    );
    expect(find.text('Кэш: 4.0 МБ'), findsOneWidget);
    expect(inGroup('osm', find.text('кэш ≈ 3.0 МБ')), findsOneWidget);
    await toggle(tester, 'osm');
    await toggle(tester, 'yandex');
    expect(find.descendant(of: find.byKey(const Key('source_ofm-liberty')), matching: find.text('≈ 3.0 МБ в кэше')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('source_yandex-hybrid')), matching: find.text('≈ 1.0 МБ в кэше')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('source_google-satellite')), matching: find.text('Нет')),
        findsOneWidget);
  });

  test('TileCacheStats counts a tile set shared by several maps once', () async {
    const satellite = MapSource(
      id: 'sat',
      name: 'Спутник',
      format: TileFormat.raster,
      storageMode: StorageMode.onlineCache,
      tileUrlTemplate: 'https://s/satellite/{z}/{x}/{y}',
    );
    const hybrid = MapSource(
      id: 'hybrid',
      name: 'Спутник + дороги',
      format: TileFormat.vector,
      storageMode: StorageMode.onlineCache,
      styleUrl: 'https://s/style/hybrid-day',
    );
    final stats = await TileCacheStats.read(
      const _Cache(
        {'https://s/satellite/{z}/{x}/{y}': 2 * _mib, 'https://s/osm/{z}/{x}/{y}': _mib},
        resources: {
          'https://s/style/hybrid-day': '{"sources": {"sat": {"type": "raster", "tiles": ["https://s/satellite/{z}/{x}/{y}"]},'
              ' "roads": {"type": "vector", "tiles": ["https://s/osm/{z}/{x}/{y}"]}}}',
        },
      ),
      [satellite, hybrid],
    );
    expect(stats.bytesOf(['hybrid']), 3 * _mib);
    expect(stats.bytesOf(['sat']), 2 * _mib);
    expect(stats.bytesOf(['sat', 'hybrid']), 3 * _mib);
  });

  testWidgets('«Только спутниковые» keeps satellite and hybrid maps', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('maps_more_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dropdown_filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('maps_dropdown')), findsNothing);
    await tester.tap(find.byKey(const Key('filter_only_satellite')));
    await tester.tap(find.byKey(const Key('filter_apply')));
    await tester.pumpAndSettle();

    expect(find.text('GOOGLE MAPS'), findsOneWidget);
    expect(find.text('ЯНДЕКС'), findsOneWidget);
    expect(find.text('OPENSTREETMAP'), findsNothing);
    expect(find.text('СВОИ КАРТЫ'), findsNothing);
  });

  testWidgets('drawer: altitude stub, closes on the scrim and on a second menu tap', (tester) async {
    await pump(tester);
    Finder drawer() => find.byKey(const Key('side_drawer'));

    await tester.tap(find.byKey(const Key('maps_menu_button')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(drawer()).dx, 0);
    await tester.tapAt(const Offset(1000, 1500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(drawer()).dx, lessThan(0));

    await tester.tap(find.byKey(const Key('maps_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('maps_menu_button')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(drawer()).dx, lessThan(0));

    await tester.tap(find.byKey(const Key('maps_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer_section_altitude')));
    await tester.pumpAndSettle();
    expect(find.text('Раздел в разработке'), findsOneWidget);
    expect(find.byKey(const Key('add_map_button')), findsNothing);
  });

  test('our server\'s maps are grouped under GOOGLE MAPS, OSM under OPENSTREETMAP', () {
    final groups = groupProviders(const [
      MapProvider(id: CatalogRepository.serverProviderId, name: 'Сервер карт', sources: [googleSat]),
      MapProvider(id: 'osm', name: 'OpenStreetMap Maps', sources: [liberty]),
      MapProvider(id: CatalogRepository.localProviderId, name: 'Установленные карты', sources: [localMbtiles]),
    ]);
    expect([for (final g in groups) '${g.id}:${g.title}'], ['osm:OPENSTREETMAP', 'google:GOOGLE MAPS']);
    expect(groups[1].sources.single.id, 'google-satellite');
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 Б');
    expect(formatBytes(2048), '2 КБ');
    expect(formatBytes(3 * 1024 * 1024), '3.0 МБ');
  });
}

final _bounds = LatLngBounds(southwest: const LatLng(47.9, 37.7), northeast: const LatLng(48.1, 37.9));

const _gib = 1024 * 1024 * 1024;

class _Storage implements StorageInfo {
  const _Storage({required this.free, required this.total});

  final int? free;
  final int? total;

  @override
  Future<int?> freeBytes(String path) async => free;

  @override
  Future<int?> totalBytes(String path) async => total;
}

const _mib = 1024 * 1024;

class _Cache implements TileCacheReader {
  const _Cache(this.bytes, {this.resources = const {}});

  final Map<String, int> bytes;
  final Map<String, String> resources;

  @override
  Future<Map<String, int>> bytesByTemplate() async => bytes;

  @override
  Future<String?> resource(String url) async => resources[url];
}

/// A 1×1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);
