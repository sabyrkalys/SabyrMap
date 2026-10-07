import 'dart:convert';
import 'dart:io' as io;

import 'package:app/map/catalog/catalog_repository.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/mediafile/mediafile_folder_service.dart';
import 'package:file/memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryUserSourcesStore implements UserSourcesStore {
  List<MapSource> saved = [];

  @override
  Future<List<MapSource>> load() async => List.of(saved);

  @override
  Future<void> save(List<MapSource> sources) async => saved = List.of(sources);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mapsDir = '/storage/maps';
  late MemoryUserSourcesStore userStore;
  setUp(() => userStore = MemoryUserSourcesStore());

  CatalogRepository repo({MemoryFileSystem? fs, http.Client? client, Set<String> hidden = const {}}) {
    final fileSystem = fs ?? MemoryFileSystem();
    return CatalogRepository(
      mapsFolder: MediaFileFolderService(subfolder: 'maps', fileSystem: fileSystem, baseDirectoryPath: mapsDir),
      httpClient: client ?? MockClient((_) async => http.Response('', 404)),
      userSources: userStore,
      fileSystem: fileSystem,
      hiddenProviderIds: hidden,
    );
  }

  test('the built-in catalog has the three required providers', () async {
    final providers = await repo().loadBuiltin();
    expect(providers.map((p) => p.id), ['osm', 'google', 'yandex']);

    final osm = providers.firstWhere((p) => p.id == 'osm').sources.map((s) => s.name);
    expect(osm, containsAll(['OpenFreeMap Liberty', 'OpenFreeMap Positron', 'OSM Standard Raster']));

    final google = providers.firstWhere((p) => p.id == 'google');
    expect(google.isolated, isTrue);
    expect(google.sources.map((s) => s.name), ['Google Map', 'Google Satellite', 'Google Terrain', 'Google Hybrid']);
    for (final s in google.sources) {
      expect(s.storageMode, StorageMode.onlineOnly, reason: s.id);
      expect(s.attribution, '© Google', reason: s.id);
      expect(s.canBeOverlay, isFalse, reason: 'Google may not be mixed with other maps: ${s.id}');
    }

    final yandex = providers.firstWhere((p) => p.id == 'yandex');
    expect(yandex.sources.map((s) => s.name), ['Яндекс Карта', 'Яндекс Спутник', 'Яндекс Гибрид']);
    for (final s in yandex.sources) {
      expect(s.storageMode, StorageMode.onlineOnly, reason: s.id);
      expect(s.attribution, '© Яндекс', reason: s.id);
      expect(s.defaultOpacity, 0.75, reason: s.id);
      expect(s.tileUrlTemplate, isNot(contains('apikey')), reason: 'the key is added at run time: ${s.id}');
    }
  });

  CatalogRepository serverRepo({http.Client? client, Uri? catalogUrl}) => CatalogRepository(
        mapsFolder: MediaFileFolderService(
            subfolder: 'maps', fileSystem: MemoryFileSystem(), baseDirectoryPath: mapsDir),
        httpClient: client ?? MockClient((_) async => http.Response('', 404)),
        userSources: userStore,
        fileSystem: MemoryFileSystem(),
        mapServerBaseUrl: 'http://tiles.test',
        catalogUrl: catalogUrl,
      );

  test('«Сервер карт» is present by default with the same maps as the server catalog', () async {
    final providers = await serverRepo().load();
    expect(providers.first.id, CatalogRepository.serverProviderId);

    final sources = {for (final s in providers.first.sources) s.id: s};
    expect(sources.keys, [
      'server-hybrid-day', 'server-hybrid-night', 'server-vector-day', 'server-vector-night', 'server-satellite',
    ]);
    expect(sources.keys, contains(CatalogRepository.defaultBaseSourceId));

    final hybrid = sources[CatalogRepository.serverHybridSourceId]!;
    expect(hybrid.format, TileFormat.vector);
    expect(hybrid.styleUrl, 'http://tiles.test/style/hybrid-day');
    expect(hybrid.downloadable, isTrue);

    final sat = sources[CatalogRepository.serverSatelliteSourceId]!;
    expect(sat.format, TileFormat.raster);
    expect(sat.tileUrlTemplate, 'http://tiles.test/satellite/{z}/{x}/{y}');
    expect(sat.maxZoom, 17);
    expect(sat.canBeOverlay, isTrue);
  });

  test('the server catalog replaces the built-in «Сервер карт» and keeps the other providers', () async {
    final body = await io.File('test/map/catalog/fixtures/server_catalog.json').readAsString();
    final r = serverRepo(client: MockClient((_) async => http.Response.bytes(utf8.encode(body), 200)));

    await r.refreshFromUrl(Uri.parse('http://api.test/maps'));
    final providers = await r.load();

    expect(providers.map((p) => p.id), ['server', 'osm']);
    final hybrid = providers.first.sources.first;
    expect(hybrid.id, 'server-hybrid-day');
    expect(hybrid.name, 'Украина · спутник + дороги');
    expect(hybrid.styleUrl, 'http://localhost:3000/style/hybrid-day');
    expect(hybrid.storageMode, StorageMode.onlineCache);
    expect(hybrid.downloadable, isTrue);
    expect(hybrid.version, 'v1');
    expect(hybrid.attribution, contains('OpenStreetMap'));
  });

  test('source ids are unique across the built-in catalog', () async {
    final ids = [for (final p in await repo().loadBuiltin()) ...p.sources.map((s) => s.id)];
    expect(ids.toSet().length, ids.length);
  });

  test('local .mbtiles files in mediafile/maps become offline sources', () async {
    final fs = MemoryFileSystem();
    fs.directory(mapsDir).createSync(recursive: true);
    fs.file('$mapsDir/Карпаты.mbtiles').writeAsBytesSync([1, 2, 3]);
    fs.file('$mapsDir/notes.txt').writeAsStringSync('ignored');

    final providers = await repo(fs: fs).load();
    final local = providers.firstWhere((p) => p.id == CatalogRepository.localProviderId);
    expect(local.name, 'Установленные карты');
    final source = local.sources.single;
    expect(source.name, 'Карпаты');
    expect(source.id, 'local-Карпаты.mbtiles');
    expect(source.storageMode, StorageMode.offlineRegion);
    expect(source.tileUrlTemplate, 'mbtiles://$mapsDir/Карпаты.mbtiles');
  });

  test('no local files → no local provider', () async {
    final providers = await repo().load();
    expect(providers.any((p) => p.id == CatalogRepository.localProviderId), isFalse);
  });

  test('refreshFromUrl replaces built-in providers with the same id', () async {
    final remote = jsonEncode({
      'version': 2,
      'providers': [
        {
          'id': 'osm',
          'name': 'OpenStreetMap Maps',
          'sources': [
            {'id': 'ofm-bright', 'name': 'OpenFreeMap Bright', 'format': 'vector', 'storageMode': 'onlineCache'},
          ],
        },
      ],
    });
    final r = repo(client: MockClient((request) async {
      expect(request.url.toString(), 'https://example.org/catalog.json');
      return http.Response.bytes(utf8.encode(remote), 200);
    }));

    final providers = await r.refreshFromUrl(Uri.parse('https://example.org/catalog.json'));
    expect(providers.single.sources.single.id, 'ofm-bright');
    final loaded = await r.load();
    expect(loaded.map((p) => p.id), ['server', 'osm', 'google', 'yandex'], reason: 'others stay');
    expect(loaded[1].sources.single.id, 'ofm-bright', reason: 'later loads use the refreshed provider');
  });

  test('a failed or broken refresh keeps the current catalog and reports the error', () async {
    final r = repo(client: MockClient((_) async => http.Response('not json', 200)));
    await expectLater(r.refreshFromUrl(Uri.parse('https://example.org/c.json')), throwsA(isA<CatalogException>()));
    expect((await r.load()).map((p) => p.id), ['server', 'osm', 'google', 'yandex']);

    final down = repo(client: MockClient((_) async => http.Response('', 503)));
    await expectLater(down.refreshFromUrl(Uri.parse('https://example.org/c.json')), throwsA(isA<CatalogException>()));
  });

  test('catalogProvider loads the catalog and refresh() swaps in the remote providers', () async {
    final remote = jsonEncode({
      'providers': [
        {'id': 'osm', 'name': 'OSM', 'sources': [{'id': 'ofm-bright', 'name': 'Bright', 'format': 'vector', 'storageMode': 'onlineCache'}]},
      ],
    });
    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo(client: MockClient((_) async => http.Response.bytes(utf8.encode(remote), 200)))),
      ],
    );
    addTearDown(container.dispose);

    expect((await container.read(catalogProvider.future)).map((p) => p.id), ['server', 'osm', 'google', 'yandex']);
    await container.read(catalogProvider.notifier).refresh(Uri.parse('https://example.org/c.json'));
    expect(container.read(catalogProvider).value![1].sources.single.id, 'ofm-bright');
  });

  test('catalogProvider fetches the server catalog in the background at start', () async {
    final body = await io.File('test/map/catalog/fixtures/server_catalog.json').readAsString();
    final requested = <Uri>[];
    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(serverRepo(
          catalogUrl: Uri.parse('http://api.test/maps'),
          client: MockClient((request) async {
            requested.add(request.url);
            return http.Response.bytes(utf8.encode(body), 200);
          }),
        )),
      ],
    );
    addTearDown(container.dispose);

    final first = await container.read(catalogProvider.future);
    expect(first.first.sources.first.name, 'Спутник + дороги', reason: 'built-in until the server answers');
    await pumpEventQueue();
    expect(requested, [Uri.parse('http://api.test/maps')]);
    expect(container.read(catalogProvider).value!.first.sources.first.name, 'Украина · спутник + дороги');
  });

  test('without a connection the start-up refresh keeps the built-in catalog', () async {
    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(serverRepo(
          catalogUrl: Uri.parse('http://api.test/maps'),
          client: MockClient((_) async => throw const io.SocketException('offline')),
        )),
      ],
    );
    addTearDown(container.dispose);

    await container.read(catalogProvider.future);
    await pumpEventQueue();
    expect(container.read(catalogProvider).value!.first.sources.first.name, 'Спутник + дороги');
  });

  group('offline region folders', () {
    test('localMapInfo: disk size of folders and files; source map, date and coverage from manifest.json', () async {
      final fs = MemoryFileSystem();
      fs.file('$mapsDir/Говерла/osm.mbtiles')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(1000, 0));
      fs.file('$mapsDir/Говерла/fonts/a.pbf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(200, 0));
      fs.file('$mapsDir/Говерла/manifest.json').writeAsStringSync(
          '{"map_id": "server-hybrid-day", "created_at": "2026-10-07T09:00:00+00:00", '
          '"bbox": [24.4, 48.1, 24.6, 48.2], "max_zoom": 15}');
      fs.file('$mapsDir/Карпаты.mbtiles').writeAsBytesSync(List.filled(300, 0));

      final info = await repo(fs: fs).localMapInfo();

      final hoverla = info['local-dir-Говерла']!;
      expect(hoverla.originSourceId, 'server-hybrid-day');
      expect(hoverla.createdAt, DateTime.utc(2026, 10, 7, 9));
      expect(hoverla.bbox, [24.4, 48.1, 24.6, 48.2]);
      expect(hoverla.maxZoom, 15);
      expect(hoverla.sizeBytes, 1200 + fs.file('$mapsDir/Говерла/manifest.json').lengthSync());
      expect(info['local-Карпаты.mbtiles']!.sizeBytes, 300);
      expect(info['local-Карпаты.mbtiles']!.originSourceId, isNull);
    });

    test('a folder with style.json is one vector map, one with only MBTiles a raster map', () async {
      final fs = MemoryFileSystem();
      fs.file('$mapsDir/Говерла/style.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"version": 8, "sources": {}, "layers": []}');
      fs.file('$mapsDir/Говерла/osm.mbtiles').createSync();
      fs.file('$mapsDir/Говерла/manifest.json').writeAsStringSync('{"attribution": "© OpenStreetMap contributors"}');
      fs.file('$mapsDir/Киев/satellite.mbtiles').createSync(recursive: true);

      final local = (await repo(fs: fs).load()).firstWhere((p) => p.id == CatalogRepository.localProviderId);
      final byName = {for (final s in local.sources) s.name: s};

      final hoverla = byName['Говерла']!;
      expect(hoverla.id, 'local-dir-Говерла');
      expect(hoverla.format, TileFormat.vector);
      expect(hoverla.storageMode, StorageMode.offlineRegion);
      expect(hoverla.styleUrl, contains('"version": 8'));
      expect(hoverla.attribution, '© OpenStreetMap contributors');

      final kyiv = byName['Киев']!;
      expect(kyiv.format, TileFormat.raster);
      expect(kyiv.tileUrlTemplate, 'mbtiles://$mapsDir/Киев/satellite.mbtiles');
    });

    test('a region still downloading is not shown yet', () async {
      final fs = MemoryFileSystem();
      fs.file('$mapsDir/Говерла/osm.mbtiles').createSync(recursive: true);
      fs.file('$mapsDir/Говерла/style.zip.part').createSync();

      final providers = await repo(fs: fs).load();
      expect(providers.any((p) => p.id == CatalogRepository.localProviderId), isFalse);
    });

    test('deleteLocalRegion removes the folder', () async {
      final fs = MemoryFileSystem();
      fs.file('$mapsDir/Говерла/style.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      final r = repo(fs: fs);

      await r.deleteLocalRegion('local-dir-Говерла');

      expect(fs.directory('$mapsDir/Говерла').existsSync(), isFalse);
    });
  });

  group('user maps', () {
    test('a style URL is added to «Установленные карты» and kept', () async {
      final r = repo();
      final source = await r.addStyleUrl(name: 'Моя топо', url: 'https://example.org/style.json');
      expect(source.format, TileFormat.vector);
      expect(source.storageMode, StorageMode.onlineCache);
      expect(source.styleUrl, 'https://example.org/style.json');
      final local = (await r.load()).firstWhere((p) => p.id == CatalogRepository.localProviderId);
      expect(local.sources.map((s) => s.name), ['Моя топо']);
      expect(userStore.saved.single.id, source.id);

      await r.removeUserSource(source.id);
      expect((await r.load()).any((p) => p.id == CatalogRepository.localProviderId), isFalse);
    });

    test('a URL that is not http(s) is refused', () async {
      await expectLater(repo().addStyleUrl(name: 'x', url: 'ftp://x'), throwsA(isA<CatalogException>()));
      await expectLater(repo().addStyleUrl(name: 'x', url: 'not a url'), throwsA(isA<CatalogException>()));
    });

    test('a JSON style file is copied into mediafile/maps and loaded as a vector map', () async {
      final fs = MemoryFileSystem();
      fs.file('/downloads/topo.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"version":8,"sources":{},"layers":[]}');
      final r = repo(fs: fs);
      await r.importStyleFile('/downloads/topo.json');

      expect(fs.file('$mapsDir/topo.json').existsSync(), isTrue);
      final source = (await r.load()).firstWhere((p) => p.id == CatalogRepository.localProviderId).sources.single;
      expect(source.name, 'topo');
      expect(source.format, TileFormat.vector);
      expect(source.storageMode, StorageMode.offlineRegion);
      expect(source.styleUrl, '{"version":8,"sources":{},"layers":[]}');
    });

    test('a JSON file that is not a MapLibre style is refused and not copied', () async {
      final fs = MemoryFileSystem();
      fs.file('/downloads/bad.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"hello":1}');
      await expectLater(repo(fs: fs).importStyleFile('/downloads/bad.json'), throwsA(isA<CatalogException>()));
      expect(fs.file('$mapsDir/bad.json').existsSync(), isFalse);
    });
  });

  test('hidden providers (Google, Яндекс for now) are left out of load()', () async {
    final providers = await repo(hidden: const {'google', 'yandex'}).load();
    expect(providers.map((p) => p.id), ['server', 'osm']);
  });
}

