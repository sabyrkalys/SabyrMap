import 'dart:async';
import 'dart:convert';

import '../models/map_models.dart';
import 'google_tiles_service.dart';
import 'yandex_tiles_service.dart';

/// What the layer manager needs from the map; implemented over
/// MapLibreMapController by [MapLibreLayerHost] and by fakes in tests.
abstract class MapLayerHost {
  /// Replaces the whole style and completes once the new style has loaded.
  /// Every source and layer added before is gone afterwards.
  Future<void> setStyleAndWait(String style);

  Future<void> addRasterSource(
    String sourceId, {
    required String tileUrl,
    required int tileSize,
    String? attribution,
    required int minZoom,
    required int maxZoom,
  });

  Future<void> addRasterLayer(String sourceId, String layerId, {required double opacity, String? belowLayerId});

  Future<void> removeLayer(String layerId);

  Future<void> removeSource(String sourceId);

  Future<void> setRasterOpacity(String layerId, double opacity);

  /// Lowest layer of the app's own annotations (tracks, waypoints, target):
  /// overlays go below it so the app's data stays on top. Null before the
  /// annotation managers exist.
  String? get annotationsBottomLayerId;
}

/// Rule violations and unreachable sources, with a message for the user.
class LayerException implements Exception {
  const LayerException(this.message);

  final String message;

  @override
  String toString() => 'LayerException: $message';
}

/// Outcome of a change that may partly fail (restoring several overlays).
class LayerChangeResult {
  const LayerChangeResult([this.problems = const []]);

  /// One user-facing line per layer that could not be (re)added.
  final List<String> problems;

  bool get ok => problems.isEmpty;
}

/// Looks sources and providers up by id.
class LayerCatalog {
  LayerCatalog(List<MapProvider> providers)
      : _providerOf = {
          for (final p in providers)
            for (final s in p.sources) s.id: p,
        },
        _sources = {
          for (final p in providers)
            for (final s in p.sources) s.id: s,
        };

  final Map<String, MapProvider> _providerOf;
  final Map<String, MapSource> _sources;

  MapSource? source(String id) => _sources[id];

  String? providerIdOf(String sourceId) => _providerOf[sourceId]?.id;

  /// Isolated providers (Google) may not share the screen with other maps.
  bool isIsolated(String sourceId) => _providerOf[sourceId]?.isolated ?? false;
}

/// Keeps the map's layer stack: one base source (a whole style) and raster
/// overlays ordered by zIndex, always below the app's own annotations.
///
/// Operations run one at a time, so an overlay added during a base change
/// lands on the new style. A failing source never breaks the others: it is
/// refused with a [LayerException], or reported in [LayerChangeResult].
class LayerManager {
  LayerManager({
    required MapLayerHost host,
    required LayerCatalog catalog,
    required GoogleTilesService google,
    required YandexTilesService yandex,
    this.maxRasterOverlays = 3,
  })  : _host = host,
        _catalog = catalog,
        _google = google,
        _yandex = yandex;

  static const int zStep = 10;
  static const int tileSize = 256;
  static const String glyphsUrl = 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf';
  static const String isolatedMessage = 'Поверх карт Google нельзя накладывать другие карты';

  final MapLayerHost _host;
  final LayerCatalog _catalog;
  final GoogleTilesService _google;
  final YandexTilesService _yandex;
  final int maxRasterOverlays;

  MapSource? _base;
  final List<ActiveLayer> _overlays = [];
  Future<void> _tail = Future.value();

  MapSource? get base => _base;

  /// Current overlays, bottom → top.
  List<ActiveLayer> getActiveLayers() => List.unmodifiable(_overlays);

  static String layerIdOf(String sourceId) => '$sourceId-layer';

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Replaces the base map; overlays are snapshotted and put back on the new
  /// style. If [source] can't be reached, the current map stays as it is.
  Future<LayerChangeResult> setBaseSource(MapSource source) => _serial(() async {
        final String style;
        if (source.format == TileFormat.vector) {
          final url = source.styleUrl;
          if (url == null || url.isEmpty) throw LayerException('У карты «${source.name}» нет адреса стиля');
          style = url;
        } else {
          style = jsonEncode(_rasterStyle(source, await _tileUrl(source)));
        }
        final snapshot = List.of(_overlays);
        await _host.setStyleAndWait(style);
        _base = source;
        _overlays.clear();
        if (_catalog.isIsolated(source.id)) {
          return LayerChangeResult(snapshot.isEmpty ? const [] : ['$isolatedMessage — наложенные слои убраны']);
        }
        return _restore(snapshot);
      });

  /// Re-adds [snapshot]'s overlays (e.g. after the style was replaced);
  /// ones that fail are reported and skipped.
  Future<LayerChangeResult> restoreOverlays(List<ActiveLayer> snapshot) => _serial(() => _restore(snapshot));

  Future<ActiveLayer> addOverlay(MapSource source, {double? opacity, bool visible = true}) =>
      _serial(() => _add(source, opacity: opacity ?? source.defaultOpacity, visible: visible));

  Future<void> removeOverlay(String sourceId) => _serial(() async {
        final index = _overlays.indexWhere((l) => l.sourceId == sourceId);
        if (index == -1) return;
        await _host.removeLayer(layerIdOf(sourceId));
        await _host.removeSource(sourceId);
        _overlays.removeAt(index);
      });

  Future<void> setOpacity(String sourceId, double opacity) => _serial(() async {
        final index = _indexOf(sourceId);
        final layer = _overlays[index];
        final clamped = opacity.clamp(0.0, 1.0);
        _overlays[index] = layer.copyWith(opacity: clamped);
        if (layer.visible) await _host.setRasterOpacity(layerIdOf(sourceId), clamped);
      });

  /// Hiding sets the map opacity to 0 but keeps the chosen opacity.
  Future<void> setVisibility(String sourceId, bool visible) => _serial(() async {
        final index = _indexOf(sourceId);
        final layer = _overlays[index];
        _overlays[index] = layer.copyWith(visible: visible);
        await _host.setRasterOpacity(layerIdOf(sourceId), visible ? layer.opacity : 0.0);
      });

  /// [orderedIds] bottom → top; must name exactly the current overlays.
  Future<void> reorderOverlays(List<String> orderedIds) => _serial(() async {
        final current = {for (final l in _overlays) l.sourceId: l};
        if (orderedIds.length != current.length || !orderedIds.every(current.containsKey)) {
          throw ArgumentError.value(orderedIds, 'orderedIds', 'must list exactly the current overlays');
        }
        for (final layer in _overlays) {
          await _host.removeLayer(layerIdOf(layer.sourceId));
        }
        _overlays.clear();
        for (var i = 0; i < orderedIds.length; i++) {
          final layer = current[orderedIds[i]]!.copyWith(zIndex: (i + 1) * zStep);
          // Added bottom → top, each right under the annotations, so each
          // new one sits above the previous.
          await _host.addRasterLayer(
            layer.sourceId,
            layerIdOf(layer.sourceId),
            opacity: layer.visible ? layer.opacity : 0.0,
            belowLayerId: _host.annotationsBottomLayerId,
          );
          _overlays.add(layer);
        }
      });

  int _indexOf(String sourceId) {
    final index = _overlays.indexWhere((l) => l.sourceId == sourceId);
    if (index == -1) throw ArgumentError.value(sourceId, 'sourceId', 'not an active overlay');
    return index;
  }

  Future<LayerChangeResult> _restore(List<ActiveLayer> snapshot) async {
    final problems = <String>[];
    final ordered = List.of(snapshot)..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    for (final layer in ordered) {
      final source = _catalog.source(layer.sourceId);
      if (source == null) {
        problems.add('Слой «${layer.sourceId}» больше не найден в каталоге');
        continue;
      }
      try {
        await _add(source, opacity: layer.opacity, visible: layer.visible, zIndex: layer.zIndex);
      } on LayerException catch (e) {
        problems.add('${source.name}: ${e.message}');
      }
    }
    return LayerChangeResult(problems);
  }

  Future<ActiveLayer> _add(MapSource source, {required double opacity, required bool visible, int? zIndex}) async {
    final base = _base;
    if (base != null && _catalog.isIsolated(base.id)) throw const LayerException(isolatedMessage);
    if (_catalog.isIsolated(source.id) || !source.canBeOverlay || source.format != TileFormat.raster) {
      throw LayerException('«${source.name}» нельзя добавить как слой');
    }
    if (_overlays.any((l) => l.sourceId == source.id)) throw LayerException('Слой «${source.name}» уже добавлен');
    if (_overlays.length >= maxRasterOverlays) {
      throw LayerException('Можно наложить не больше $maxRasterOverlays слоёв');
    }

    final url = await _tileUrl(source);
    final z = zIndex ?? (_overlays.isEmpty ? zStep : _overlays.last.zIndex + zStep);
    final above = _overlays.where((l) => l.zIndex > z).toList();
    final below = above.isEmpty ? _host.annotationsBottomLayerId : layerIdOf(above.first.sourceId);
    final clamped = opacity.clamp(0.0, 1.0);

    await _host.addRasterSource(
      source.id,
      tileUrl: url,
      tileSize: tileSize,
      attribution: source.attribution,
      minZoom: source.minZoom,
      maxZoom: source.maxZoom,
    );
    await _host.addRasterLayer(source.id, layerIdOf(source.id), opacity: visible ? clamped : 0.0, belowLayerId: below);
    final layer = ActiveLayer(sourceId: source.id, type: MapLayerType.overlay, opacity: clamped, visible: visible, zIndex: z);
    _overlays
      ..add(layer)
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return layer;
  }

  /// The raster tile URL, with the key/session and access check for Google
  /// and Яндекс.
  Future<String> _tileUrl(MapSource source) async {
    try {
      switch (_catalog.providerIdOf(source.id)) {
        case 'google':
          await _google.verifyAccess(source);
          return await _google.tileUrlTemplate(source);
        case 'yandex':
          await _yandex.verifyAccess(source);
          return _yandex.tileUrlTemplate(source);
      }
    } on GoogleTilesException catch (e) {
      throw LayerException(e.message);
    } on YandexTilesException catch (e) {
      throw LayerException(e.message);
    } on ArgumentError {
      throw LayerException('У карты «${source.name}» нет адреса тайлов');
    }
    final template = source.tileUrlTemplate;
    if (template == null || template.isEmpty) throw LayerException('У карты «${source.name}» нет адреса тайлов');
    return template;
  }

  Map<String, dynamic> _rasterStyle(MapSource source, String tileUrl) => {
        'version': 8,
        'glyphs': glyphsUrl,
        'sources': {
          source.id: {
            'type': 'raster',
            'tiles': [tileUrl],
            'tileSize': tileSize,
            'minzoom': source.minZoom,
            'maxzoom': source.maxZoom,
            if (source.attribution != null) 'attribution': source.attribution,
          },
        },
        'layers': [
          {
            'id': 'background',
            'type': 'background',
            'paint': {'background-color': '#e5e3df'},
          },
          {'id': layerIdOf(source.id), 'type': 'raster', 'source': source.id},
        ],
      };
}
