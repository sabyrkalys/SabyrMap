import 'dart:io';

import 'package:app/maps/file_maps/map_bounds.dart';
import 'package:app/maps/offline/offline_area_controller.dart';
import 'package:app/maps/offline/offline_area_estimator.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'tile_budget_test.dart' show tile;

void main() {
  final oneTile = tile(600, 345, 10);

  test('one zoom-10 tile on zoom 10..10 is 1 tile', () {
    final r = OfflineAreaEstimator.estimate(bounds: oneTile, minZoom: 10, maxZoom: 10, sourceIds: const ['topo']);
    expect(r.estimatedTileCount, 1);
  });

  test('zoom 10..11 is 5 tiles', () {
    final r = OfflineAreaEstimator.estimate(bounds: oneTile, minZoom: 10, maxZoom: 11, sourceIds: const ['topo']);
    expect(r.estimatedTileCount, 5);
  });

  test('bytes = tiles × 25000; several sources multiply', () {
    final r = OfflineAreaEstimator.estimate(bounds: oneTile, minZoom: 10, maxZoom: 11, sourceIds: const ['a', 'b']);
    expect(r.estimatedTileCount, 10);
    expect(r.estimatedBytes, 10 * 25000);
  });

  test('validation', () {
    expect(
      () => OfflineAreaEstimator.estimate(bounds: oneTile, minZoom: 12, maxZoom: 10, sourceIds: const []),
      throwsArgumentError,
    );
    expect(
      () => OfflineAreaEstimator.estimate(
        bounds: const MapBounds(northLat: 1, southLat: 1, westLon: 0, eastLon: 1),
        minZoom: 1,
        maxZoom: 2,
        sourceIds: const [],
      ),
      throwsArgumentError,
    );
  });

  test('controller: start, progress, pause/resume, complete, cancel, clear cache', () async {
    final root = Directory.systemTemp.createTempSync('offline_');
    addTearDown(() => root.deleteSync(recursive: true));
    final storage = StorageService(StoragePaths.forRoot(root.path));
    final c = OfflineAreaController(const OfflineAreaEstimator(), storage);
    final req = OfflineAreaEstimator.estimate(bounds: oneTile, minZoom: 10, maxZoom: 11, sourceIds: const ['topo']);

    await c.start(req);
    expect(c.isRunning, isTrue);
    expect(c.progress!.totalTiles, 5);
    expect(() => c.start(req), throwsStateError);
    c.updateProgress(downloadedTiles: 2, bytesDownloaded: 50000);
    expect(c.progress!.fraction, 0.4);
    await c.pause();
    expect(c.isRunning, isFalse);
    c.updateProgress(downloadedTiles: 4);
    expect(c.progress!.downloadedTiles, 2);
    await c.resume();
    c.updateProgress(downloadedTiles: 5);
    expect(c.status, OfflineAreaStatus.completed);
    await c.cancel();
    expect(c.progress, isNull);

    final cache = Directory(c.cacheFolder('topo'))..createSync(recursive: true);
    File(p.join(cache.path, '1.png')).writeAsBytesSync([1]);
    await c.clearData('topo');
    expect(cache.existsSync(), isFalse);
    await c.clearData('topo');
    expect(() => c.clearData('../x'), throwsArgumentError);
  });
}
