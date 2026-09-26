import 'dart:async';

import 'package:maplibre_gl/maplibre_gl.dart';

import 'layer_manager.dart';

/// [MapLayerHost] over the real MapLibre controller.
///
/// MapLibre reports a finished style only through MapLibreMap's
/// onStyleLoadedCallback, so the map screen must call [notifyStyleLoaded]
/// from there; [setStyleAndWait] waits for that call.
class MapLibreLayerHost implements MapLayerHost {
  MapLibreLayerHost(this._controller, {this.styleTimeout = const Duration(seconds: 30)});

  final MapLibreMapController _controller;
  final Duration styleTimeout;
  Completer<void>? _styleLoaded;

  void notifyStyleLoaded() {
    final pending = _styleLoaded;
    _styleLoaded = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  @override
  Future<void> setStyleAndWait(String style) async {
    final loaded = _styleLoaded = Completer<void>();
    await _controller.setStyle(style);
    try {
      await loaded.future.timeout(styleTimeout);
    } on TimeoutException {
      throw const LayerException('Карта не загрузилась, проверьте подключение');
    }
  }

  @override
  Future<void> addRasterSource(
    String sourceId, {
    required String tileUrl,
    required int tileSize,
    String? attribution,
    required int minZoom,
    required int maxZoom,
  }) {
    return _controller.addSource(
      sourceId,
      RasterSourceProperties(
        tiles: [tileUrl],
        tileSize: tileSize.toDouble(),
        minzoom: minZoom.toDouble(),
        maxzoom: maxZoom.toDouble(),
        attribution: attribution,
      ),
    );
  }

  @override
  Future<void> addRasterLayer(String sourceId, String layerId, {required double opacity, String? belowLayerId}) {
    return _controller.addRasterLayer(
      sourceId,
      layerId,
      RasterLayerProperties(rasterOpacity: opacity),
      belowLayerId: belowLayerId,
    );
  }

  @override
  Future<void> removeLayer(String layerId) => _controller.removeLayer(layerId);

  @override
  Future<void> removeSource(String sourceId) => _controller.removeSource(sourceId);

  @override
  Future<void> setRasterOpacity(String layerId, double opacity) =>
      _controller.setLayerProperties(layerId, RasterLayerProperties(rasterOpacity: opacity));

  /// Track lines are the lowest annotation layer (MapLibreMap's default
  /// annotation order is line, symbol, circle, fill).
  @override
  String? get annotationsBottomLayerId {
    final ids = _controller.lineManager?.layerIds;
    return ids == null || ids.isEmpty ? null : ids.first;
  }
}
