import 'package:app/map/models/map_models.dart';
import 'package:app/map/prefetch/neighbor_prefetcher.dart';
import 'package:app/map/regions/server_region_service.dart' show NetworkInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../services/offline_service_test.dart' show FakeOfflineBackend;

class FakeNetwork implements NetworkInfo {
  FakeNetwork(this.wifi);

  final bool wifi;

  @override
  Future<bool> isOnWifi() async => wifi;
}

void main() {
  final visible = LatLngBounds(southwest: const LatLng(48.13, 24.47), northeast: const LatLng(48.18, 24.505));
  const server = MapSource(
    id: 'server-hybrid-day',
    name: 'Спутник + дороги',
    styleUrl: 'http://tiles.test/style/hybrid-day',
    format: TileFormat.vector,
    storageMode: StorageMode.onlineCache,
    maxZoom: 20,
  );
  late FakeOfflineBackend backend;

  setUp(() => backend = FakeOfflineBackend());

  NeighborPrefetcher prefetcher({bool wifi = true}) => NeighborPrefetcher(backend: backend, network: FakeNetwork(wifi));

  test('loads the neighbourhood as temporary regions and deletes them when done', () async {
    backend.eventsToSend = [Success()];

    await prefetcher().onIdle(source: server, visible: visible, zoom: 13);
    await pumpEventQueue();

    final downloads = backend.calls.where((c) => c.startsWith('download')).toList();
    expect(downloads, ['download http://tiles.test/style/hybrid-day z13.0-13.0', 'download http://tiles.test/style/hybrid-day z14.0-14.0']);
    expect(backend.regions, isEmpty, reason: 'tiles stay in the ambient cache; the regions go');
  });

  test('a new movement cancels what is still loading', () async {
    final p = prefetcher();
    await p.onIdle(source: server, visible: visible, zoom: 13); // no Success: still loading
    await pumpEventQueue();
    expect(backend.regions, hasLength(2));

    await p.cancel();

    expect(backend.regions, isEmpty);
  });

  test('nothing is loaded off Wi-Fi, while recording a track, or for maps that may not be stored', () async {
    await prefetcher(wifi: false).onIdle(source: server, visible: visible, zoom: 13);
    await prefetcher().onIdle(source: server, visible: visible, zoom: 13, recording: true);
    const google = MapSource(id: 'g', name: 'Google', format: TileFormat.raster, storageMode: StorageMode.onlineOnly);
    await prefetcher().onIdle(source: google, visible: visible, zoom: 13);
    const local = MapSource(
        id: 'l', name: 'Local', styleUrl: '{"version":8}', format: TileFormat.vector, storageMode: StorageMode.offlineRegion);
    await prefetcher().onIdle(source: local, visible: visible, zoom: 13);
    await pumpEventQueue();

    expect(backend.calls, isEmpty);
  });

  test('leftover prefetch regions from an earlier run are removed, saved areas are kept', () async {
    final definition = OfflineRegionDefinition(bounds: visible, mapStyleUrl: 'http://x', minZoom: 1, maxZoom: 2);
    await backend.download(definition, metadata: {prefetchMetadataKey: true});
    await backend.download(definition, metadata: {'name': 'Мой участок'});

    await prefetcher().cleanUpLeftovers();

    expect(backend.regions.values.single.metadata['name'], 'Мой участок');
  });
}
