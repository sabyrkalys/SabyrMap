import 'dart:async';

import 'package:maplibre_gl/maplibre_gl.dart';

import 'hybrid_road_style.dart';
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
      isTilesetUrl(tileUrl)
          ? RasterSourceProperties(url: tileUrl, tileSize: tileSize.toDouble(), attribution: attribution)
          : RasterSourceProperties(
              tiles: [tileUrl],
              tileSize: tileSize.toDouble(),
              minzoom: minZoom.toDouble(),
              maxzoom: maxZoom.toDouble(),
              attribution: attribution,
            ),
    );
  }

  @override
  Future<void> addRasterLayer(
    String sourceId,
    String layerId, {
    required double opacity,
    RasterColor color = RasterColor.none,
    String? belowLayerId,
  }) {
    return _controller.addRasterLayer(sourceId, layerId, _paint(opacity, color), belowLayerId: belowLayerId);
  }

  @override
  Future<void> removeLayer(String layerId) => _controller.removeLayer(layerId);

  @override
  Future<void> removeSource(String sourceId) => _controller.removeSource(sourceId);

  @override
  Future<void> setRasterOpacity(String layerId, double opacity, {RasterColor color = RasterColor.none}) =>
      _controller.setLayerProperties(layerId, _paint(opacity, color));

  static RasterLayerProperties _paint(double opacity, RasterColor color) => RasterLayerProperties(
        rasterOpacity: opacity,
        rasterBrightnessMin: color.brightnessMin,
        rasterBrightnessMax: color.brightnessMax,
        rasterContrast: color.contrast,
        rasterSaturation: color.saturation,
      );

  @override
  Future<void> addStyleSource(String sourceId, Map<String, dynamic> source) =>
      _controller.addSource(sourceId, VectorSourceProperties.fromJson(source));

  /// The style JSON's layout and paint, flattened as maplibre_gl wants them.
  static LayerProperties? _properties(Map<String, dynamic> layer) {
    final json = <String, dynamic>{
      ...?(layer['layout'] as Map<String, dynamic>?),
      ...?(layer['paint'] as Map<String, dynamic>?),
    };
    return switch (layer['type']) {
      'line' => LineLayerProperties.fromJson(json),
      'symbol' => SymbolLayerProperties.fromJson(json),
      'fill' => FillLayerProperties.fromJson(json),
      'circle' => CircleLayerProperties.fromJson(json),
      'fill-extrusion' => FillExtrusionLayerProperties.fromJson(json),
      _ => null,
    };
  }

  @override
  Future<void> addStyleLayer(Map<String, dynamic> layer, {String? belowLayerId}) async {
    final properties = _properties(layer);
    if (properties == null) return;
    await _controller.addLayer(
      layer['source'] as String,
      layer['id'] as String,
      properties,
      belowLayerId: belowLayerId,
      enableInteraction: false,
      sourceLayer: layer['source-layer'] as String?,
      minzoom: (layer['minzoom'] as num?)?.toDouble(),
      maxzoom: (layer['maxzoom'] as num?)?.toDouble(),
      filter: layer['filter'],
    );
  }

  @override
  Future<void> setStyleLayerProperties(Map<String, dynamic> layer) async {
    final properties = _properties(layer);
    if (properties != null) await _controller.setLayerProperties(layer['id'] as String, properties);
  }

  @override
  Future<void> setLayerVisibility(String layerId, bool visible) => _controller.setLayerVisibility(layerId, visible);

  /// Every property not given here is reset to MapLibre's default, so the
  /// layout of our styles' lines (round cap and join) is repeated.
  @override
  Future<void> setLinePaint(String layerId, LinePaint paint) => _controller.setLayerProperties(
        layerId,
        LineLayerProperties(
          lineWidth: paint.width,
          lineColor: paint.color,
          lineOpacity: paint.opacity,
          lineCap: 'round',
          lineJoin: 'round',
        ),
      );

  @override
  Future<List<String>> layerIds() async => [for (final id in await _controller.getLayerIds()) '$id'];

  /// Track lines are the lowest annotation layer (MapLibreMap's default
  /// annotation order is line, symbol, circle, fill).
  @override
  String? get annotationsBottomLayerId {
    final ids = _controller.lineManager?.layerIds;
    return ids == null || ids.isEmpty ? null : ids.first;
  }
}
