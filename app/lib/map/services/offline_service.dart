import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:maplibre_gl/maplibre_gl.dart'
    show DownloadRegionStatus, InProgress, LatLngBounds, OfflineRegion, OfflineRegionDefinition, OfflineRegionStatus, Success;

import '../models/map_models.dart';

/// The maplibre_gl offline functions (global, native), behind an interface
/// so [OfflineService] can be tested.
abstract class OfflineBackend {
  Future<OfflineRegion> download(
    OfflineRegionDefinition definition, {
    required Map<String, dynamic> metadata,
    void Function(DownloadRegionStatus)? onEvent,
  });

  Future<List<OfflineRegion>> list();

  Future<OfflineRegionStatus> status(int id);

  Future<void> delete(int id);

  Future<void> pause(int id);

  Future<void> resume(int id);
}

class MapLibreOfflineBackend implements OfflineBackend {
  const MapLibreOfflineBackend();

  @override
  Future<OfflineRegion> download(
    OfflineRegionDefinition definition, {
    required Map<String, dynamic> metadata,
    void Function(DownloadRegionStatus)? onEvent,
  }) =>
      ml.downloadOfflineRegion(definition, metadata: metadata, onEvent: onEvent);

  @override
  Future<List<OfflineRegion>> list() => ml.getListOfRegions();

  @override
  Future<OfflineRegionStatus> status(int id) => ml.getOfflineRegionStatus(id);

  @override
  Future<void> delete(int id) async => ml.deleteOfflineRegion(id);

  @override
  Future<void> pause(int id) => ml.pauseOfflineRegionDownload(id);

  @override
  Future<void> resume(int id) => ml.resumeOfflineRegionDownload(id);
}

class OfflineException implements Exception {
  const OfflineException(this.message);

  final String message;

  @override
  String toString() => 'OfflineException: $message';
}

/// One saved area as shown in the UI.
class OfflineRegionInfo {
  const OfflineRegionInfo({
    required this.id,
    required this.name,
    required this.sourceId,
    required this.sizeBytes,
    required this.progress,
    required this.isComplete,
  });

  final int id;
  final String name;
  final String? sourceId;
  final int sizeBytes;

  /// 0–100.
  final double progress;
  final bool isComplete;
}

/// Saved map areas («Сохранить участок карты») via MapLibre offline regions.
///
/// A region is downloaded by style URL, so only vector sources can be saved.
/// That also rules out onlineOnly sources (Google, Яндекс — their terms
/// forbid it) and raster OSM (the openstreetmap.org tile servers forbid bulk
/// downloads).
class OfflineService {
  OfflineService({OfflineBackend backend = const MapLibreOfflineBackend()}) : _backend = backend;

  final OfflineBackend _backend;

  static bool canSaveRegion(MapSource source) =>
      source.storageMode == StorageMode.onlineCache && source.format == TileFormat.vector && source.styleUrl != null;

  /// [onProgress] gets 0–100.
  Future<OfflineRegion> createRegion({
    required MapSource source,
    required LatLngBounds bounds,
    required double minZoom,
    required double maxZoom,
    required String name,
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
  }) async {
    if (source.storageMode == StorageMode.onlineOnly) {
      throw OfflineException('«${source.name}» работает только онлайн — сохранить участок нельзя');
    }
    if (!canSaveRegion(source)) {
      throw OfflineException('Для карты «${source.name}» сохранение участка недоступно');
    }
    final top = math.min(maxZoom, source.maxZoom.toDouble());
    final bottom = math.max(minZoom, source.minZoom.toDouble());
    if (bottom > top) throw const OfflineException('Минимальный масштаб больше максимального');

    return _backend.download(
      OfflineRegionDefinition(bounds: bounds, mapStyleUrl: source.styleUrl!, minZoom: bottom, maxZoom: top),
      metadata: {'name': name, 'sourceId': source.id},
      onEvent: (event) {
        if (event is InProgress) {
          onProgress?.call(event.progress);
        } else if (event is Success) {
          onProgress?.call(100);
        } else {
          onError?.call('Не удалось сохранить участок карты');
        }
      },
    );
  }

  Future<List<OfflineRegionInfo>> listRegions() async {
    final regions = await _backend.list();
    return [
      for (final region in regions)
        await () async {
          final status = await _backend.status(region.id);
          return OfflineRegionInfo(
            id: region.id,
            name: region.metadata['name'] as String? ?? 'Участок ${region.id}',
            sourceId: region.metadata['sourceId'] as String?,
            sizeBytes: status.completedResourceSize,
            progress: status.downloadProgress,
            isComplete: status.isComplete,
          );
        }(),
    ];
  }

  Future<void> deleteRegion(int id) => _backend.delete(id);

  Future<void> pauseRegion(int id) => _backend.pause(id);

  Future<void> resumeRegion(int id) => _backend.resume(id);

  /// Bytes of all saved areas together.
  Future<int> getTotalCacheSize() async {
    var total = 0;
    for (final region in await listRegions()) {
      total += region.sizeBytes;
    }
    return total;
  }
}

final offlineServiceProvider = Provider<OfflineService>((ref) => OfflineService());
