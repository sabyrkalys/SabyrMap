import 'package:app/map/models/map_models.dart';
import 'package:app/map/services/offline_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class FakeOfflineBackend implements OfflineBackend {
  final regions = <int, OfflineRegion>{};
  final statuses = <int, OfflineRegionStatus>{};
  final calls = <String>[];
  int _next = 1;
  List<DownloadRegionStatus> eventsToSend = [];

  @override
  Future<OfflineRegion> download(
    OfflineRegionDefinition definition, {
    required Map<String, dynamic> metadata,
    void Function(DownloadRegionStatus)? onEvent,
  }) async {
    final region = OfflineRegion(id: _next++, definition: definition, metadata: metadata);
    regions[region.id] = region;
    calls.add('download ${definition.mapStyleUrl} z${definition.minZoom}-${definition.maxZoom}');
    for (final e in eventsToSend) {
      onEvent?.call(e);
    }
    return region;
  }

  @override
  Future<List<OfflineRegion>> list() async => regions.values.toList();

  @override
  Future<OfflineRegionStatus> status(int id) async => statuses[id]!;

  @override
  Future<void> delete(int id) async {
    calls.add('delete $id');
    regions.remove(id);
  }

  @override
  Future<void> pause(int id) async => calls.add('pause $id');

  @override
  Future<void> resume(int id) async => calls.add('resume $id');
}

OfflineRegionStatus status({required int bytes, required double progress, bool complete = false}) =>
    OfflineRegionStatus.fromMap({
      'completedResourceCount': 1,
      'requiredResourceCount': 2,
      'completedResourceSize': bytes,
      'isComplete': complete,
      'downloadProgress': progress,
    });

void main() {
  const liberty = MapSource(
    id: 'ofm-liberty',
    name: 'OpenFreeMap Liberty',
    format: TileFormat.vector,
    storageMode: StorageMode.onlineCache,
    styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
    maxZoom: 14,
  );
  const google = MapSource(
    id: 'google-satellite',
    name: 'Google Satellite',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineOnly,
  );
  const osmRaster = MapSource(
    id: 'osm-standard',
    name: 'OSM Standard Raster',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineCache,
    tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  final bounds = LatLngBounds(southwest: const LatLng(47.9, 37.7), northeast: const LatLng(48.1, 37.9));

  late FakeOfflineBackend backend;
  late OfflineService service;

  setUp(() {
    backend = FakeOfflineBackend();
    service = OfflineService(backend: backend);
  });

  test('canSaveRegion: only vector onlineCache sources', () {
    expect(OfflineService.canSaveRegion(liberty), isTrue);
    expect(OfflineService.canSaveRegion(google), isFalse);
    expect(OfflineService.canSaveRegion(osmRaster), isFalse);
  });

  test('createRegion downloads the style for the area, zoom clamped to the source', () async {
    final events = <double>[];
    final region = await service.createRegion(
      source: liberty,
      bounds: bounds,
      minZoom: 10,
      maxZoom: 18,
      name: 'Донецк',
      onProgress: events.add,
    );
    expect(backend.calls.single, 'download https://tiles.openfreemap.org/styles/liberty z10.0-14.0');
    expect(region.metadata, {'name': 'Донецк', 'sourceId': 'ofm-liberty'});
  });

  test('progress and errors are reported', () async {
    backend.eventsToSend = [InProgress(40), Success()];
    final progress = <double>[];
    await service.createRegion(source: liberty, bounds: bounds, minZoom: 10, maxZoom: 12, name: 'a', onProgress: progress.add);
    expect(progress, [40, 100]);
  });

  test('onlineOnly and raster sources are refused with a clear message', () async {
    await expectLater(
      service.createRegion(source: google, bounds: bounds, minZoom: 10, maxZoom: 12, name: 'x'),
      throwsA(isA<OfflineException>().having((e) => e.message, 'message', contains('только онлайн'))),
    );
    await expectLater(
      service.createRegion(source: osmRaster, bounds: bounds, minZoom: 10, maxZoom: 12, name: 'x'),
      throwsA(isA<OfflineException>()),
    );
    expect(backend.calls, isEmpty);
  });

  test('min zoom above max zoom is refused', () async {
    await expectLater(
      service.createRegion(source: liberty, bounds: bounds, minZoom: 13, maxZoom: 11, name: 'x'),
      throwsA(isA<OfflineException>()),
    );
  });

  test('listRegions joins metadata and status; total size sums them', () async {
    final a = await service.createRegion(source: liberty, bounds: bounds, minZoom: 10, maxZoom: 12, name: 'A');
    final b = await service.createRegion(source: liberty, bounds: bounds, minZoom: 10, maxZoom: 12, name: 'B');
    backend.statuses[a.id] = status(bytes: 1000, progress: 100, complete: true);
    backend.statuses[b.id] = status(bytes: 250, progress: 30);

    final regions = await service.listRegions();
    expect(regions.map((r) => (r.name, r.sourceId, r.sizeBytes, r.progress, r.isComplete)), [
      ('A', 'ofm-liberty', 1000, 100.0, true),
      ('B', 'ofm-liberty', 250, 30.0, false),
    ]);
    expect(await service.getTotalCacheSize(), 1250);
  });

  test('delete, pause, resume go to the backend', () async {
    final a = await service.createRegion(source: liberty, bounds: bounds, minZoom: 10, maxZoom: 12, name: 'A');
    await service.pauseRegion(a.id);
    await service.resumeRegion(a.id);
    await service.deleteRegion(a.id);
    expect(backend.calls.sublist(1), ['pause ${a.id}', 'resume ${a.id}', 'delete ${a.id}']);
  });
}
