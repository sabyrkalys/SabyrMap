import 'package:app/map/catalog/catalog_repository.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/map/orthophoto/orthophoto_extent.dart';
import 'package:app/map/services/google_tiles_service.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/services/yandex_tiles_service.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../services/layer_manager_test.dart' show FakeHost;
import '../state/map_layers_controller_test.dart' show MemoryMapStateStore;

MapSource ortho(String name) => MapSource(
  id: 'ortho-$name.mbtiles',
  name: name,
  format: TileFormat.raster,
  storageMode: StorageMode.offlineRegion,
  tileUrlTemplate: 'mbtiles:///o/$name.mbtiles',
  canBeOverlay: true,
);

// Доброполье и Авдеевка (≈60 км друг от друга), файл без границ.
final dobro = ortho('Доброполье');
final avd = ortho('Авдеевка');
final unknown = ortho('Без границ');
const dobroExtent = MbtilesExtent(minZoom: 10, maxZoom: 20, west: 37.047, south: 48.441, east: 37.140, north: 48.490);
const avdExtent = MbtilesExtent(minZoom: 12, maxZoom: 19, west: 37.70, south: 48.11, east: 37.78, north: 48.16);

/// Окно ~10×10 км над Добропольем.
const overDobro = GeoBox(west: 37.03, south: 48.42, east: 37.16, north: 48.51);

class _FakeReader implements MbtilesExtentReader {
  _FakeReader(this.extents);

  final Map<String, MbtilesExtent?> extents;
  final reads = <String>[];

  @override
  Future<MbtilesExtent?> read(String path) async {
    reads.add(path);
    return extents[path];
  }
}

class _Catalog extends CatalogNotifier {
  _Catalog(this.providers);

  final List<MapProvider> providers;
  int reloads = 0;

  @override
  Future<List<MapProvider>> build() async => providers;

  @override
  Future<void> reload() async {
    reloads++;
    state = AsyncData(providers);
  }
}

void main() {
  group('choice by the screen', () {
    final extents = {dobro.id: dobroExtent, avd.id: avdExtent, unknown.id: null};

    test('only the files around the screen; unknown bounds always', () {
      final picked = orthophotosFor([dobro, avd, unknown], extents, viewport: overDobro, zoom: 15);
      expect(picked, [dobro, unknown]);
    });

    test('a neighbouring territory comes in a screen before it is reached', () {
      // Окно чуть западнее Доброполья: файл за краем, но в соседнем экране.
      const west = GeoBox(west: 36.85, south: 48.42, east: 37.00, north: 48.51);
      expect(orthophotosFor([dobro], extents, viewport: west, zoom: 15), [dobro]);
      const far = GeoBox(west: 36.20, south: 48.42, east: 36.35, north: 48.51);
      expect(orthophotosFor([dobro], extents, viewport: far, zoom: 15), isEmpty);
    });

    test('zoomed far out (below the file zooms) — none', () {
      const country = GeoBox(west: 30, south: 45, east: 40, north: 52);
      expect(orthophotosFor([dobro, avd], extents, viewport: country, zoom: 6), isEmpty);
      expect(orthophotosFor([dobro, avd], extents, viewport: country, zoom: 11), [dobro, avd]);
    });

    test('GeoBox.expanded and intersects', () {
      const box = GeoBox(west: 0, south: 0, east: 1, north: 2);
      final wide = box.expanded(1);
      expect((wide.west, wide.south, wide.east, wide.north), (-1.0, -2.0, 2.0, 4.0));
      expect(dobroExtent.intersects(overDobro), isTrue);
      expect(avdExtent.intersects(overDobro), isFalse);
    });
  });

  group('platform reader', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('sabyrmap/mbtiles');
    late List<String> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        final path = (call.arguments as Map)['path'] as String;
        calls.add(path);
        if (path.contains('broken')) throw PlatformException(code: 'mbtiles_failed');
        return {'minZoom': 10, 'maxZoom': 20, 'west': 37.047, 'south': 48.441, 'east': 37.14, 'north': 48.49};
      });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    test('reads once per file; a broken file gives unknown bounds', () async {
      final reader = PlatformMbtilesExtentReader();
      final first = await reader.read('/o/a.mbtiles');
      await reader.read('/o/a.mbtiles');
      expect(calls, ['/o/a.mbtiles']);
      expect((first!.minZoom, first.maxZoom, first.west, first.north), (10, 20, 37.047, 48.49));
      expect(await reader.read('/o/broken.mbtiles'), isNull);
    });
  });

  group('controller', () {
    const base = MapSource(
      id: CatalogRepository.defaultBaseSourceId,
      name: 'Спутник + дороги',
      format: TileFormat.raster,
      storageMode: StorageMode.onlineOnly,
      tileUrlTemplate: 'http://t/{z}/{x}/{y}',
    );
    late FakeHost host;
    late _Catalog catalog;
    late _FakeReader reader;

    Future<ProviderContainer> attached({MapState? saved}) async {
      final providers = [
        const MapProvider(id: 'server', name: 'Сервер', sources: [base]),
        MapProvider(id: CatalogRepository.orthophotoProviderId, name: 'Ортофотопланы', sources: [dobro, avd]),
      ];
      catalog = _Catalog(providers);
      reader = _FakeReader({'/o/Доброполье.mbtiles': dobroExtent, '/o/Авдеевка.mbtiles': avdExtent});
      final c = ProviderContainer(
        overrides: [
          mapStateStoreProvider.overrideWithValue(MemoryMapStateStore(saved)),
          catalogProvider.overrideWith(() => catalog),
          mbtilesExtentReaderProvider.overrideWithValue(reader),
        ],
      );
      addTearDown(c.dispose);
      host = FakeHost();
      await c.read(mapLayersProvider.notifier).attach(
        LayerManager(
          host: host,
          catalog: LayerCatalog(providers),
          google: GoogleTilesService(apiKey: '', httpClient: MockClient((_) async => http.Response('', 500))),
          yandex: YandexTilesService(apiKey: '', httpClient: MockClient((_) async => http.Response('', 500))),
        ),
      );
      return c;
    }

    test('off: nothing is put on the map', () async {
      final c = await attached();
      await c.read(mapLayersProvider.notifier).updateOrthophotos(overDobro, 15);
      expect(host.sources.keys, isNot(contains(dobro.id)));
      expect(reader.reads, isEmpty);
    });

    test('on: re-reads the folder and shows only the territory on screen', () async {
      final c = await attached();
      final notifier = c.read(mapLayersProvider.notifier);
      expect(await notifier.setOrthophotosOn(true), 2);
      expect(catalog.reloads, 1);
      expect(c.read(mapLayersProvider).orthophotosOn, isTrue);

      await notifier.updateOrthophotos(overDobro, 15);
      expect(host.sources.keys, contains(dobro.id));
      expect(host.sources.keys, isNot(contains(avd.id)));
    });

    test('moving away swaps territories; off removes them all', () async {
      final c = await attached();
      final notifier = c.read(mapLayersProvider.notifier);
      await notifier.setOrthophotosOn(true);
      await notifier.updateOrthophotos(overDobro, 15);
      const overAvd = GeoBox(west: 37.68, south: 48.10, east: 37.80, north: 48.17);
      await notifier.updateOrthophotos(overAvd, 15);
      expect(host.sources.keys, contains(avd.id));
      expect(host.sources.keys, isNot(contains(dobro.id)));
      await notifier.setOrthophotosOn(false);
      expect(host.sources.keys, isNot(contains(avd.id)));
      expect(c.read(mapLayersProvider).orthophotosOn, isFalse);
    });

    test('a file already shown is not re-added when the map moves a little', () async {
      final c = await attached();
      final notifier = c.read(mapLayersProvider.notifier);
      await notifier.setOrthophotosOn(true);
      await notifier.updateOrthophotos(overDobro, 15);
      host.calls.clear();
      const nudged = GeoBox(west: 37.04, south: 48.43, east: 37.17, north: 48.52);
      await notifier.updateOrthophotos(nudged, 15);
      expect(host.calls, isEmpty);
    });

    test('remembered: after a restart the first update shows them again', () async {
      final c = await attached(
        saved: const MapState(baseSourceId: null, overlays: [], favoriteIds: [], presets: [], orthophotosOn: true),
      );
      expect(c.read(mapLayersProvider).orthophotosOn, isTrue);
      await c.read(mapLayersProvider.notifier).updateOrthophotos(overDobro, 15);
      expect(host.sources.keys, contains(dobro.id));
    });

    test('one added as an overlay turns the switch on; the switch hides and shows it, keeping the layer', () async {
      final c = await attached();
      final notifier = c.read(mapLayersProvider.notifier);
      await notifier.addOverlay(dobro);
      expect(c.read(mapLayersProvider).orthophotosOn, isTrue);
      final layerId = LayerManager.layerIdOf(dobro.id);
      expect(host.opacities[layerId], 1);

      await notifier.setOrthophotosOn(false);
      expect(c.read(mapLayersProvider).overlays.single.visible, isFalse);
      expect(host.opacities[layerId], 0);
      expect(host.sources.keys, contains(dobro.id), reason: 'the overlay stays, only hidden');

      await notifier.setOrthophotosOn(true);
      expect(c.read(mapLayersProvider).overlays.single.visible, isTrue);
      expect(host.opacities[layerId], 1);
    });

    test('turning on also shows an orthophoto overlay hidden with its eye', () async {
      final c = await attached();
      final notifier = c.read(mapLayersProvider.notifier);
      await notifier.setOrthophotosOn(false);
      await notifier.addOverlay(avd);
      await notifier.setVisibility(avd.id, false);
      await notifier.setOrthophotosOn(true);
      expect(c.read(mapLayersProvider).overlays.single.visible, isTrue);
    });
  });
}
