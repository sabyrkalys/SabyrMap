import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:maplibre_gl/maplibre_gl.dart' show DownloadRegionStatus, LatLng, LatLngBounds, OfflineRegionDefinition;

import '../models/map_models.dart';
import '../regions/server_region_service.dart' show ConnectivityNetworkInfo, NetworkInfo;
import '../services/offline_service.dart';
import 'prefetch_planner.dart';

/// Metadata key of the short-lived regions below; OfflineService hides them.
const String prefetchMetadataKey = 'prefetch';

/// Loads the tiles around the visible area while the map stands still, so
/// a pan or a zoom-in shows cached tiles at once.
///
/// It uses a temporary MapLibre offline region per [PrefetchPart] and
/// deletes it as soon as it finished: the tiles stay in MapLibre's ambient
/// cache, only the "keep forever" mark goes. A new camera movement cancels
/// whatever is still loading.
class NeighborPrefetcher {
  NeighborPrefetcher({
    OfflineBackend backend = const MapLibreOfflineBackend(),
    NetworkInfo network = const ConnectivityNetworkInfo(),
    this.maxTiles = 60,
  })  : _backend = backend,
        _network = network;

  final OfflineBackend _backend;
  final NetworkInfo _network;
  final int maxTiles;

  final Set<int> _running = {};
  int _generation = 0;
  LatLng? _lastCenter;

  /// Only styles fetched over the network; never Google/Яндекс (their terms
  /// forbid storing tiles), never local files.
  static bool canPrefetch(MapSource source) {
    final style = source.styleUrl;
    return source.storageMode == StorageMode.onlineCache &&
        style != null &&
        (style.startsWith('https://') || style.startsWith('http://'));
  }

  /// The map stopped: plan and start loading. [recording] = a track is
  /// being recorded (prefetch is off then, to spare battery and data).
  Future<void> onIdle({
    required MapSource? source,
    required LatLngBounds visible,
    required double zoom,
    bool recording = false,
  }) async {
    final generation = ++_generation;
    final previous = _lastCenter;
    _lastCenter = LatLng(
      (visible.southwest.latitude + visible.northeast.latitude) / 2,
      (visible.southwest.longitude + visible.northeast.longitude) / 2,
    );
    if (source == null || recording || !canPrefetch(source)) return;
    try {
      if (!await _network.isOnWifi() || generation != _generation) return;
    } catch (_) {
      return; // network state unknown: don't spend data
    }
    final parts = planPrefetch(
      visible: visible,
      zoom: zoom,
      previousCenter: previous,
      maxZoom: source.maxZoom,
      maxTiles: maxTiles,
    );
    for (final part in parts) {
      if (generation != _generation) return;
      unawaited(_load(source.styleUrl!, part, generation));
    }
  }

  /// The map started moving: stop loading the old neighbourhood.
  Future<void> cancel() async {
    _generation++;
    final ids = List.of(_running);
    _running.clear();
    for (final id in ids) {
      await _backend.delete(id).catchError((_) {});
    }
  }

  Future<void> _load(String styleUrl, PrefetchPart part, int generation) async {
    final finished = Completer<void>();
    void onEvent(DownloadRegionStatus event) {
      if (event is ml.Success || event is ml.Error) {
        if (!finished.isCompleted) finished.complete();
      }
    }

    try {
      final region = await _backend.download(
        OfflineRegionDefinition(
          bounds: part.bounds,
          mapStyleUrl: styleUrl,
          minZoom: part.zoom.toDouble(),
          maxZoom: part.zoom.toDouble(),
        ),
        metadata: {prefetchMetadataKey: true},
        onEvent: onEvent,
      );
      if (generation != _generation) {
        await _backend.delete(region.id);
        return;
      }
      _running.add(region.id);
      await finished.future;
      if (_running.remove(region.id)) await _backend.delete(region.id);
    } catch (_) {
      // Prefetch is best effort: a failure only means a slower next pan.
    }
  }

  /// Temporary regions left by a previous run (app killed mid-prefetch).
  Future<void> cleanUpLeftovers() async {
    try {
      for (final region in await _backend.list()) {
        if (region.metadata[prefetchMetadataKey] == true) await _backend.delete(region.id);
      }
    } catch (_) {}
  }
}

final neighborPrefetcherProvider = Provider<NeighborPrefetcher>((ref) => NeighborPrefetcher());
