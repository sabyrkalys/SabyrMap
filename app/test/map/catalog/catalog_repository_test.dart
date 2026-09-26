import 'dart:convert';

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

  CatalogRepository repo({MemoryFileSystem? fs, http.Client? client}) {
    final fileSystem = fs ?? MemoryFileSystem();
    return CatalogRepository(
      mapsFolder: MediaFileFolderService(subfolder: 'maps', fileSystem: fileSystem, baseDirectoryPath: mapsDir),
      httpClient: client ?? MockClient((_) async => http.Response('', 404)),
      userSources: userStore,
      fileSystem: fileSystem,
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

  test('refreshFromUrl replaces the built-in providers with the remote catalog', () async {
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
    expect((await r.load()).first.sources.single.id, 'ofm-bright', reason: 'later loads use the refreshed catalog');
  });

  test('a failed or broken refresh keeps the current catalog and reports the error', () async {
    final r = repo(client: MockClient((_) async => http.Response('not json', 200)));
    await expectLater(r.refreshFromUrl(Uri.parse('https://example.org/c.json')), throwsA(isA<CatalogException>()));
    expect((await r.load()).map((p) => p.id), ['osm', 'google', 'yandex']);

    final down = repo(client: MockClient((_) async => http.Response('', 503)));
    await expectLater(down.refreshFromUrl(Uri.parse('https://example.org/c.json')), throwsA(isA<CatalogException>()));
  });

  test('catalogProvider loads the catalog and refresh() swaps in the remote one', () async {
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

    expect((await container.read(catalogProvider.future)).map((p) => p.id), ['osm', 'google', 'yandex']);
    await container.read(catalogProvider.notifier).refresh(Uri.parse('https://example.org/c.json'));
    expect(container.read(catalogProvider).value!.single.sources.single.id, 'ofm-bright');
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
}

