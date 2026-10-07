import 'dart:convert';

import 'package:app/map/models/map_models.dart';
import 'package:app/map/regions/file_downloader.dart';
import 'package:app/map/regions/regions_api.dart';
import 'package:app/map/regions/server_region_service.dart';
import 'package:app/mediafile/mediafile_folder_service.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng, LatLngBounds;

class FakeNetwork implements NetworkInfo {
  FakeNetwork(this.wifi);

  bool wifi;

  @override
  Future<bool> isOnWifi() async => wifi;
}

class FakeStorage implements StorageInfo {
  const FakeStorage(this.free);

  final int? free;

  @override
  Future<int?> freeBytes(String path) async => free;

  @override
  Future<int?> totalBytes(String path) async => null;
}

const hybrid = MapSource(
  id: 'server-hybrid-day',
  name: 'Спутник + дороги',
  styleUrl: 'http://tiles.test/style/hybrid-day',
  format: TileFormat.vector,
  storageMode: StorageMode.onlineCache,
  downloadable: true,
);

/// What the server's worker would produce for a hybrid region.
Map<String, List<int>> regionFiles({bool evilZip = false}) {
  final style = {
    'version': 8,
    'glyphs': 'file://{{REGION_DIR}}/fonts/{fontstack}/{range}.pbf',
    'sprite': 'file://{{REGION_DIR}}/sprites/sabyr',
    'sources': {
      'osm': {'type': 'vector', 'url': 'mbtiles://{{REGION_DIR}}/osm.mbtiles'},
      'overview': {'type': 'raster', 'url': 'mbtiles://{{REGION_DIR}}/overview.mbtiles'},
    },
    'layers': [],
  };
  final zip = Archive()
    ..add(ArchiveFile.string('style.json', jsonEncode(style)))
    ..add(ArchiveFile.bytes('fonts/Noto Sans Regular/0-255.pbf', [1, 2, 3]))
    ..add(ArchiveFile.bytes('sprites/sabyr.json', utf8.encode('{}')));
  if (evilZip) zip.add(ArchiveFile.bytes('../../escape.txt', [6, 6, 6]));
  return {
    'osm.mbtiles': utf8.encode('osm tiles'),
    'overview.mbtiles': utf8.encode('overview tiles'),
    'style.zip': ZipEncoder().encodeBytes(zip),
    'manifest.json': utf8.encode('{"attribution": "© OSM"}'),
  };
}

void main() {
  final bounds = LatLngBounds(southwest: const LatLng(48.14, 24.47), northeast: const LatLng(48.18, 24.53));
  late MemoryFileSystem fs;
  late Map<String, List<int>> files;
  late List<String> calls;
  late List<String> statuses;
  late FakeNetwork network;

  setUp(() {
    fs = MemoryFileSystem();
    files = regionFiles();
    calls = [];
    statuses = ['running', 'ready'];
    network = FakeNetwork(true);
  });

  Map<String, dynamic> job(String status) => {
        'id': 'job1',
        'map_id': 'server-hybrid-day',
        'status': status,
        'progress': status == 'ready' ? 1.0 : 0.5,
        'error': status == 'failed' ? 'pmtiles extract failed' : null,
        'files': status == 'ready'
            ? [
                for (final e in files.entries)
                  {'name': e.key, 'size': e.value.length, 'sha256': sha256.convert(e.value).toString()},
              ]
            : [],
      };

  ServerRegionService service({int? free = 1 << 30}) {
    final client = MockClient((request) async {
      final path = request.url.path;
      calls.add('${request.method} $path');
      if (request.method == 'POST' && path == '/regions') return http.Response(jsonEncode(job('queued')), 201);
      if (path == '/regions/estimate') {
        return http.Response(jsonEncode({'total_bytes': 5000, 'max_bytes': 10000, 'allowed': true}), 200);
      }
      if (path == '/regions/job1') return http.Response(jsonEncode(job(statuses.removeAt(0))), 200);
      final name = Uri.decodeComponent(path.split('/').last);
      return http.Response.bytes(files[name]!, 200);
    });
    return ServerRegionService(
      api: RegionsApi(baseUrl: 'http://api.test', httpClient: client),
      mapsFolder: MediaFileFolderService(subfolder: 'maps', fileSystem: fs, baseDirectoryPath: '/maps'),
      network: network,
      storage: FakeStorage(free),
      pollInterval: Duration.zero,
    );
  }

  test('installs a region: waits for the server, downloads, unpacks the style with real paths', () async {
    final stages = <RegionStage>[];

    final folder = await service().install(
      source: hybrid,
      bounds: bounds,
      maxZoom: 15,
      name: 'Говерла',
      onProgress: (p) => stages.add(p.stage),
    );

    expect(folder.path, '/maps/Говерла');
    expect(calls.first, 'POST /regions');
    expect(stages.toSet(), {RegionStage.preparing, RegionStage.downloading, RegionStage.installing});
    expect(fs.file('/maps/Говерла/osm.mbtiles').readAsStringSync(), 'osm tiles');
    expect(fs.file('/maps/Говерла/fonts/Noto Sans Regular/0-255.pbf').readAsBytesSync(), [1, 2, 3]);
    expect(fs.file('/maps/Говерла/style.zip').existsSync(), isFalse);
    final style = jsonDecode(fs.file('/maps/Говерла/style.json').readAsStringSync()) as Map<String, dynamic>;
    expect(style['glyphs'], 'file:///maps/Говерла/fonts/{fontstack}/{range}.pbf');
    expect((style['sources'] as Map)['osm']['url'], 'mbtiles:///maps/Говерла/osm.mbtiles');
    expect(jsonEncode(style), isNot(contains('{{REGION_DIR}}')));
  });

  test('later regions take the overview tiles from the world package', () async {
    fs.file('/maps/${ServerRegionService.overviewFolderName}/overview.mbtiles')
      ..createSync(recursive: true)
      ..writeAsStringSync('world');

    await service().install(source: hybrid, bounds: bounds, maxZoom: 15, name: 'Говерла');

    final style = jsonDecode(fs.file('/maps/Говерла/style.json').readAsStringSync()) as Map<String, dynamic>;
    expect((style['sources'] as Map)['overview']['url'],
        'mbtiles:///maps/${ServerRegionService.overviewFolderName}/overview.mbtiles');
    expect(fs.file('/maps/Говерла/overview.mbtiles').existsSync(), isFalse);
  });

  test('ensureOverview downloads the world package once', () async {
    final s = service();
    expect(await s.hasOverview(), isFalse);

    await s.ensureOverview(source: hybrid);
    expect(await s.hasOverview(), isTrue);
    final requests = calls.length;

    await s.ensureOverview(source: hybrid);
    expect(calls.length, requests, reason: 'already there: no new request');
  });

  test('Wi-Fi only refuses to start on mobile data', () async {
    network.wifi = false;
    await expectLater(
      service().install(source: hybrid, bounds: bounds, maxZoom: 15, name: 'x'),
      throwsA(isA<RegionException>().having((e) => e.message, 'message', contains('Wi-Fi'))),
    );
    expect(calls, isEmpty);

    await service().install(source: hybrid, bounds: bounds, maxZoom: 15, name: 'x', wifiOnly: false);
    expect(fs.file('/maps/x/style.json').existsSync(), isTrue);
  });

  test('a region the server failed to cut is reported', () async {
    statuses = ['failed'];
    await expectLater(
      service().install(source: hybrid, bounds: bounds, maxZoom: 15, name: 'x'),
      throwsA(isA<RegionException>().having((e) => e.message, 'message', contains('pmtiles extract failed'))),
    );
  });

  test('cancel while the server prepares stops before downloading', () async {
    final cancel = CancelToken()..cancel();
    await expectLater(
      service().install(source: hybrid, bounds: bounds, maxZoom: 15, name: 'x', cancel: cancel),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(calls.where((c) => c.contains('/download/')), isEmpty);
  });

  test('archive entries cannot escape the region folder', () async {
    files = regionFiles(evilZip: true);
    await service().install(source: hybrid, bounds: bounds, maxZoom: 15, name: 'x');
    expect(fs.file('/escape.txt').existsSync(), isFalse);
    expect(fs.file('/maps/escape.txt').existsSync(), isFalse);
  });

  test('check reports the size, the free space and whether it fits', () async {
    final roomy = await service().check(source: hybrid, bounds: bounds, maxZoom: 15);
    expect(roomy.estimate.totalBytes, 5000);
    expect(roomy.canSave, isTrue);

    final full = await service(free: 1000).check(source: hybrid, bounds: bounds, maxZoom: 15);
    expect(full.fitsOnPhone, isFalse);
    expect(full.canSave, isFalse);
  });

  test('the world box keeps its width (LatLng wraps longitude 180 to -180)', () {
    final bbox = bboxOf(ServerRegionService.world);
    expect(bbox[0], -180);
    expect(bbox[2], greaterThan(179.9));
  });

  test('folder names are safe and never empty', () {
    expect(ServerRegionService.folderNameFor('Говерла / Пип-Иван: 2'), 'Говерла Пип-Иван 2');
    expect(ServerRegionService.folderNameFor('  '), 'Участок');
    expect(ServerRegionService.folderNameFor('..'), 'Участок');
  });

  test('only maps the server marks downloadable can be saved; zoom is capped at 17', () {
    expect(ServerRegionService.canDownload(hybrid), isTrue);
    expect(ServerRegionService.canDownload(const MapSource(
        id: 'ofm', name: 'OFM', format: TileFormat.vector, storageMode: StorageMode.onlineCache)), isFalse);
    expect(ServerRegionService.zoomLimit(const MapSource(
        id: 'h', name: 'h', format: TileFormat.vector, storageMode: StorageMode.onlineCache, maxZoom: 20)), 17);
  });
}
