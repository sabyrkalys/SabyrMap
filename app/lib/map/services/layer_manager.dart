import 'dart:async';
import 'dart:convert';

import '../../maps/color/layer_color_settings.dart';
import '../catalog/catalog_repository.dart';
import '../models/map_models.dart';
import 'google_tiles_service.dart';
import 'hybrid_road_style.dart';
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

  Future<void> addRasterLayer(
    String sourceId,
    String layerId, {
    required double opacity,
    RasterColor color = RasterColor.none,
    String? belowLayerId,
  });

  Future<void> removeLayer(String layerId);

  Future<void> removeSource(String sourceId);

  /// Sets a raster layer's opacity together with its [color]: MapLibre
  /// resets every paint property not given, so both always go together.
  Future<void> setRasterOpacity(String layerId, double opacity, {RasterColor color = RasterColor.none});

  /// Shows or hides any layer (also one that came with the style).
  Future<void> setLayerVisibility(String layerId, bool visible);

  /// Changes the paint of a line layer that came with the style.
  Future<void> setLinePaint(String layerId, LinePaint paint);

  /// Ids of all the map's layers now, bottom → top.
  Future<List<String>> layerIds();

  /// Lowest layer of the app's own annotations (tracks, waypoints, target):
  /// overlays go below it so the app's data stays on top. Null before the
  /// annotation managers exist.
  String? get annotationsBottomLayerId;
}

/// A raster layer's colour correction in MapLibre's terms.
class RasterColor {
  const RasterColor({this.brightnessMin = 0, this.brightnessMax = 1, this.contrast = 0, this.saturation = 0});

  static const RasterColor none = RasterColor();

  /// [LayerColorSettings] as MapLibre paint: brightness narrows the
  /// brightness range, inversion swaps its ends. The tint has no MapLibre
  /// equivalent and is not shown.
  factory RasterColor.of(LayerColorSettings s) {
    final b = s.brightness.clamp(-1.0, 1.0);
    final low = b > 0 ? b : 0.0;
    final high = b < 0 ? 1 + b : 1.0;
    return RasterColor(
      brightnessMin: s.inverted ? high : low,
      brightnessMax: s.inverted ? low : high,
      contrast: (s.contrast - 1).clamp(-1.0, 1.0),
      saturation: (s.saturation - 1).clamp(-1.0, 1.0),
    );
  }

  final double brightnessMin;
  final double brightnessMax;

  /// −1..1, 0 — unchanged.
  final double contrast;

  /// −1..1, 0 — unchanged.
  final double saturation;

  @override
  bool operator ==(Object other) =>
      other is RasterColor &&
      other.brightnessMin == brightnessMin &&
      other.brightnessMax == brightnessMax &&
      other.contrast == contrast &&
      other.saturation == saturation;

  @override
  int get hashCode => Object.hash(brightnessMin, brightnessMax, contrast, saturation);
}

/// Whether [url] points at a whole tileset (TileJSON-like, e.g. a local
/// .mbtiles file) rather than a {z}/{x}/{y} template. MapLibre only opens
/// mbtiles:// through a source's `url`, and then takes the zoom range from
/// the file's metadata so it can overzoom past the file's last level.
bool isTilesetUrl(String url) => url.startsWith('mbtiles://');

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
        _styles = MapStyleResolver(catalog: catalog, google: google, yandex: yandex);

  static const int zStep = 10;
  static const int tileSize = 256;
  static const String glyphsUrl = 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf';
  static const String isolatedMessage = 'Поверх карт Google нельзя накладывать другие карты';
  static const String orthophotoOverlayMessage = 'Ортофотопланы включаются кнопкой ортофотопланов';

  final MapLayerHost _host;
  final LayerCatalog _catalog;
  final MapStyleResolver _styles;
  final int maxRasterOverlays;

  MapSource? _base;
  final List<ActiveLayer> _overlays = [];

  /// Orthophotos shown over the map: each file is one territory, so they
  /// don't cover each other and aren't counted against [maxRasterOverlays].
  /// They sit above the overlays, under the base style's roads.
  final List<MapSource> _orthophotos = [];
  Future<void> _tail = Future.value();

  /// The built-in world map under every map ([setWorld]).
  static const String worldSourceId = 'sabyr-world';
  String? _worldPath;
  double _worldOpacity = 1;

  /// The chosen map's own layers (its style), to hide the map with
  /// [setMapVisible]; the style background stays under the world map.
  List<String> _styleLayerIds = const [];
  bool _mapVisible = true;

  bool get mapVisible => _mapVisible;

  /// Shows or hides the chosen map: its style layers, except the background.
  /// Overlays, orthophotos and the world map stay. Kept across base changes.
  Future<void> setMapVisible(bool visible) => _serial(() async {
        _mapVisible = visible;
        await _applyMapVisible();
      });

  Future<void> _applyMapVisible() async {
    for (final id in _styleLayerIds) {
      if (id.contains('background')) continue;
      try {
        await _host.setLayerVisibility(id, _mapVisible);
      } catch (_) {}
    }
  }

  /// Opacity and colour shared by all orthophotos.
  double _orthophotoOpacity = 1;
  LayerColorSettings _orthophotoColor = const LayerColorSettings();

  /// Colour correction of overlays, by source id; kept while the overlay is
  /// on the map (also across base changes), dropped when it is removed.
  final Map<String, LayerColorSettings> _colors = {};

  MapSource? get base => _base;

  RasterColor _colorOf(String sourceId) {
    final settings = _colors[sourceId];
    return settings == null ? RasterColor.none : RasterColor.of(settings);
  }

  /// The world map file (.mbtiles) to lay under every map, right above the
  /// style's background: it shows wherever the map has no tiles. Null — none.
  Future<void> setWorld(String? mbtilesPath, {double? opacity}) => _serial(() async {
        if (opacity != null) _worldOpacity = opacity.clamp(0.0, 1.0);
        if (_worldPath != null && _base != null) {
          try {
            await _host.removeLayer(layerIdOf(worldSourceId));
            await _host.removeSource(worldSourceId);
          } catch (_) {}
        }
        _worldPath = mbtilesPath;
        if (_base != null) await _addWorld();
      });

  Future<void> setWorldOpacity(double opacity) => _serial(() async {
        _worldOpacity = opacity.clamp(0.0, 1.0);
        if (_worldPath != null && _base != null) {
          await _host.setRasterOpacity(layerIdOf(worldSourceId), _worldOpacity);
        }
      });

  /// Cosmetic like [_tweakRoads]: a map without the world under it still works.
  Future<void> _addWorld() async {
    final path = _worldPath;
    final base = _base;
    if (path == null || base == null || _catalog.isIsolated(base.id)) return;
    try {
      final ids = await _host.layerIds();
      final background = ids.indexWhere((id) => id.contains('background'));
      final ceiling = background + 1 < ids.length ? ids[background + 1] : null;
      await _host.addRasterSource(
        worldSourceId,
        tileUrl: 'mbtiles://$path',
        tileSize: tileSize,
        minZoom: 0,
        maxZoom: 5,
      );
      await _host.addRasterLayer(worldSourceId, layerIdOf(worldSourceId), opacity: _worldOpacity, belowLayerId: ceiling);
    } catch (_) {}
  }

  /// Opacity and/or colour of all orthophotos, now and for those put on
  /// the map later.
  Future<void> setOrthophotoPaint({double? opacity, LayerColorSettings? color}) => _serial(() async {
        if (opacity != null) _orthophotoOpacity = opacity.clamp(0.0, 1.0);
        if (color != null) _orthophotoColor = color;
        for (final source in _orthophotos) {
          await _host.setRasterOpacity(layerIdOf(source.id), _orthophotoOpacity, color: RasterColor.of(_orthophotoColor));
        }
      });

  /// Colour correction of [sourceId]; for an overlay not on the map yet it
  /// applies once it is added.
  Future<void> setColor(String sourceId, LayerColorSettings settings) => _serial(() async {
        settings.isIdentity ? _colors.remove(sourceId) : _colors[sourceId] = settings;
        final index = _overlays.indexWhere((l) => l.sourceId == sourceId);
        if (index == -1) return;
        final layer = _overlays[index];
        await _host.setRasterOpacity(layerIdOf(sourceId), layer.visible ? layer.opacity : 0.0, color: _colorOf(sourceId));
      });

  /// Current overlays, bottom → top.
  List<ActiveLayer> getActiveLayers() => List.unmodifiable(_overlays);

  /// Orthophotos on the map now.
  List<MapSource> getOrthophotos() => List.unmodifiable(_orthophotos);

  /// Where overlays go: under the lowest orthophoto, or under the
  /// annotations when there are none.
  String? get _overlayCeiling =>
      _orthophotos.isEmpty ? _host.annotationsBottomLayerId : layerIdOf(_orthophotos.first.id);

  /// Shows exactly [sources] as orthophotos (an empty list removes them).
  /// Only the difference is applied: ones already shown stay as they are
  /// (no flicker while the map moves), ones no longer wanted are removed,
  /// new ones added. A source already on the map as the base or an overlay
  /// is skipped; one that fails is reported and left out.
  Future<LayerChangeResult> setOrthophotos(List<MapSource> sources) => _serial(() async {
        final wanted = {for (final s in sources) s.id};
        for (final source in List.of(_orthophotos)) {
          if (wanted.contains(source.id)) continue;
          try {
            await _host.removeLayer(layerIdOf(source.id));
            await _host.removeSource(source.id);
          } catch (_) {}
          _orthophotos.remove(source);
        }
        final shown = {for (final s in _orthophotos) s.id};
        return _addOrthophotos([
          for (final s in sources)
            if (!shown.contains(s.id)) s,
        ]);
      });

  Future<LayerChangeResult> _addOrthophotos(List<MapSource> sources) async {
    final base = _base;
    if (sources.isEmpty) return const LayerChangeResult();
    if (base != null && _catalog.isIsolated(base.id)) {
      return const LayerChangeResult(['$isolatedMessage — ортофотопланы не показаны']);
    }
    final problems = <String>[];
    final ceiling = await _orthophotoCeiling();
    for (final source in sources) {
      if (source.id == base?.id || _overlays.any((l) => l.sourceId == source.id)) continue;
      try {
        await _host.addRasterSource(
          source.id,
          tileUrl: await _styles.tileUrl(source),
          tileSize: tileSize,
          attribution: source.attribution,
          minZoom: source.minZoom,
          maxZoom: source.maxZoom,
        );
        // Each one right under the roads: above the overlays and the
        // orthophotos added before it.
        await _host.addRasterLayer(
          source.id,
          layerIdOf(source.id),
          opacity: _orthophotoOpacity,
          color: RasterColor.of(_orthophotoColor),
          belowLayerId: ceiling,
        );
        _orthophotos.add(source);
      } on Exception catch (e) {
        problems.add('${source.name}: $e');
      }
    }
    return LayerChangeResult(problems);
  }

  /// Where orthophotos go: under the lowest road layer of our styles
  /// (road_layers in tools/build/styles/build_styles.py), so roads, borders
  /// and labels stay on top of the photo; under the annotations for a base
  /// without such roads.
  Future<String?> _orthophotoCeiling() async {
    try {
      for (final id in await _host.layerIds()) {
        if (id.startsWith('road-')) return id;
      }
    } catch (_) {}
    return _host.annotationsBottomLayerId;
  }

  static String layerIdOf(String sourceId) => '$sourceId-layer';

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Replaces the base map; overlays are snapshotted and put back on the new
  /// style. If [source] can't be reached, the current map stays as it is.
  Future<LayerChangeResult> setBaseSource(MapSource source) => _serial(() async {
        final style = await _styles.styleOf(source);
        final snapshot = List.of(_overlays);
        final orthophotos = List.of(_orthophotos);
        await _host.setStyleAndWait(style);
        _base = source;
        try {
          _styleLayerIds = await _host.layerIds();
        } catch (_) {
          _styleLayerIds = const [];
        }
        await _tweakRoads(style);
        await _addWorld();
        if (!_mapVisible) await _applyMapVisible();
        _overlays.clear();
        _orthophotos.clear();
        if (_catalog.isIsolated(source.id)) {
          _colors.clear();
          return LayerChangeResult(
            snapshot.isEmpty && orthophotos.isEmpty ? const [] : ['$isolatedMessage — наложенные слои убраны'],
          );
        }
        // The new style has none of them: orthophotos first, so the
        // overlays are put back under them.
        final shown = await _addOrthophotos(orthophotos);
        final restored = await _restore(snapshot);
        return LayerChangeResult([...shown.problems, ...restored.problems]);
      });

  /// Our look of the hybrid styles' roads ([hybridRoadPaint]). Cosmetic:
  /// a layer that can't be changed keeps the server's look.
  Future<void> _tweakRoads(String style) async {
    for (final entry in (hybridRoadPaint(style) ?? const <String, LinePaint>{}).entries) {
      try {
        await _host.setLinePaint(entry.key, entry.value);
      } catch (_) {}
    }
  }

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
        _colors.remove(sourceId);
      });

  Future<void> setOpacity(String sourceId, double opacity) => _serial(() async {
        final index = _indexOf(sourceId);
        final layer = _overlays[index];
        final clamped = opacity.clamp(0.0, 1.0);
        _overlays[index] = layer.copyWith(opacity: clamped);
        if (layer.visible) await _host.setRasterOpacity(layerIdOf(sourceId), clamped, color: _colorOf(sourceId));
      });

  /// Hiding sets the map opacity to 0 but keeps the chosen opacity.
  Future<void> setVisibility(String sourceId, bool visible) => _serial(() async {
        final index = _indexOf(sourceId);
        final layer = _overlays[index];
        _overlays[index] = layer.copyWith(visible: visible);
        await _host.setRasterOpacity(layerIdOf(sourceId), visible ? layer.opacity : 0.0, color: _colorOf(sourceId));
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
            color: _colorOf(layer.sourceId),
            belowLayerId: _overlayCeiling,
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
    if (_catalog.providerIdOf(source.id) == CatalogRepository.orthophotoProviderId) {
      throw const LayerException(orthophotoOverlayMessage);
    }
    if (_overlays.any((l) => l.sourceId == source.id)) throw LayerException('Слой «${source.name}» уже добавлен');
    if (_orthophotos.any((s) => s.id == source.id)) {
      throw LayerException('«${source.name}» уже показан среди ортофотопланов');
    }
    if (_overlays.length >= maxRasterOverlays) {
      throw LayerException('Можно наложить не больше $maxRasterOverlays слоёв');
    }

    final url = await _styles.tileUrl(source);
    final z = zIndex ?? (_overlays.isEmpty ? zStep : _overlays.last.zIndex + zStep);
    final above = _overlays.where((l) => l.zIndex > z).toList();
    final below = above.isEmpty ? _overlayCeiling : layerIdOf(above.first.sourceId);
    final clamped = opacity.clamp(0.0, 1.0);

    await _host.addRasterSource(
      source.id,
      tileUrl: url,
      tileSize: tileSize,
      attribution: source.attribution,
      minZoom: source.minZoom,
      maxZoom: source.maxZoom,
    );
    await _host.addRasterLayer(
      source.id,
      layerIdOf(source.id),
      opacity: visible ? clamped : 0.0,
      color: _colorOf(source.id),
      belowLayerId: below,
    );
    final layer = ActiveLayer(sourceId: source.id, type: MapLayerType.overlay, opacity: clamped, visible: visible, zIndex: z);
    _overlays
      ..add(layer)
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return layer;
  }
}

/// The style MapLibre gets for a base map: a vector map's own style (URL or
/// JSON), or a one-layer style around a raster map's tiles. Shared by the
/// map ([LayerManager]) and the map previews.
class MapStyleResolver {
  MapStyleResolver({
    required LayerCatalog catalog,
    required GoogleTilesService google,
    required YandexTilesService yandex,
  })  : _catalog = catalog,
        _google = google,
        _yandex = yandex;

  final LayerCatalog _catalog;
  final GoogleTilesService _google;
  final YandexTilesService _yandex;

  Future<String> styleOf(MapSource source) async {
    if (source.format == TileFormat.vector) {
      final url = source.styleUrl;
      if (url == null || url.isEmpty) throw LayerException('У карты «${source.name}» нет адреса стиля');
      return url;
    }
    return jsonEncode(_rasterStyle(source, await tileUrl(source)));
  }

  /// The raster tile URL, with the key/session and access check for Google
  /// and Яндекс.
  Future<String> tileUrl(MapSource source) async {
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
        'glyphs': LayerManager.glyphsUrl,
        'sources': {
          source.id: {
            'type': 'raster',
            if (isTilesetUrl(tileUrl))
              'url': tileUrl
            else ...{
              'tiles': [tileUrl],
              'minzoom': source.minZoom,
              'maxzoom': source.maxZoom,
            },
            'tileSize': LayerManager.tileSize,
            if (source.attribution != null) 'attribution': source.attribution,
          },
        },
        'layers': [
          {
            'id': 'background',
            'type': 'background',
            'paint': {'background-color': '#e5e3df'},
          },
          {'id': LayerManager.layerIdOf(source.id), 'type': 'raster', 'source': source.id},
        ],
      };
}
