import 'dart:async';
import 'dart:convert';

import 'package:app/map/models/map_models.dart';
import 'package:app/maps/color/layer_color_settings.dart';
import 'package:app/map/services/google_tiles_service.dart';
import 'package:app/map/services/hybrid_road_style.dart';
import 'dart:convert' as convert;

import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/services/yandex_tiles_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vector_overlay_test.dart' show hybridStyle;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records every call the manager makes on the map.
class FakeHost implements MapLayerHost {
  final calls = <String>[];
  final sources = <String, String>{}; // id → tile URL
  final layers = <String>[]; // bottom → top, overlay layers only
  final opacities = <String, double>{};
  final colors = <String, RasterColor>{};
  String? style;
  Completer<void>? styleGate;

  @override
  String? annotationsBottomLayerId = 'lines_0';

  @override
  Future<void> setStyleAndWait(String style) async {
    calls.add('setStyle');
    this.style = style;
    sources.clear();
    layers.clear();
    opacities.clear();
    await styleGate?.future;
  }

  @override
  Future<void> addRasterSource(String sourceId,
      {required String tileUrl, required int tileSize, String? attribution, required int minZoom, required int maxZoom}) async {
    calls.add('addSource $sourceId');
    sources[sourceId] = tileUrl;
  }

  @override
  Future<void> addRasterLayer(
    String sourceId,
    String layerId, {
    required double opacity,
    RasterColor color = RasterColor.none,
    String? belowLayerId,
  }) async {
    colors[layerId] = color;
    calls.add('addLayer $layerId below ${belowLayerId ?? 'top'}');
    final index = belowLayerId == null ? -1 : layers.indexOf(belowLayerId);
    if (index == -1) {
      layers.add(layerId);
    } else {
      layers.insert(index, layerId);
    }
    opacities[layerId] = opacity;
  }

  @override
  Future<void> removeLayer(String layerId) async {
    calls.add('removeLayer $layerId');
    layers.remove(layerId);
  }

  @override
  Future<void> removeSource(String sourceId) async {
    calls.add('removeSource $sourceId');
    sources.remove(sourceId);
  }

  @override
  Future<void> setRasterOpacity(String layerId, double opacity, {RasterColor color = RasterColor.none}) async {
    calls.add('opacity $layerId $opacity');
    colors[layerId] = color;
    opacities[layerId] = opacity;
  }

  final linePaints = <String, LinePaint>{};

  /// Hidden layers (any, also the style's own).
  final hidden = <String>{};

  @override
  Future<void> invalidateTileCache() async => calls.add('invalidateCache');

  /// Style-JSON layers added or re-set, by id.
  final styleLayers_ = <String, Map<String, dynamic>>{};

  @override
  Future<void> addStyleSource(String sourceId, Map<String, dynamic> source) async {
    calls.add('addStyleSource $sourceId');
    sources[sourceId] = '${source['url'] ?? (source['tiles'] as List?)?.first}';
  }

  @override
  Future<void> addStyleLayer(Map<String, dynamic> layer, {String? belowLayerId}) async {
    final layerId = layer['id'] as String;
    calls.add('addStyleLayer $layerId below ${belowLayerId ?? 'top'}');
    final index = belowLayerId == null ? -1 : layers.indexOf(belowLayerId);
    index == -1 ? layers.add(layerId) : layers.insert(index, layerId);
    styleLayers_[layerId] = layer;
  }

  @override
  Future<void> setStyleLayerProperties(Map<String, dynamic> layer) async {
    calls.add('styleLayer ${layer['id']}');
    styleLayers_[layer['id'] as String] = layer;
  }

  @override
  Future<void> setLayerVisibility(String layerId, bool visible) async {
    calls.add('visibility $layerId $visible');
    visible ? hidden.remove(layerId) : hidden.add(layerId);
  }

  @override
  Future<void> setLinePaint(String layerId, LinePaint paint) async {
    calls.add('linePaint $layerId');
    linePaints[layerId] = paint;
  }

  /// The style's own layers, all below [layers].
  List<String> styleLayers = [];

  @override
  Future<List<String>> layerIds() async => [...styleLayers, ...layers];
}

void main() {
  const liberty = MapSource(
    id: 'ofm-liberty',
    name: 'OpenFreeMap Liberty',
    format: TileFormat.vector,
    storageMode: StorageMode.onlineCache,
    styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
  );
  const osm = MapSource(
    id: 'osm-standard',
    name: 'OSM Standard Raster',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineCache,
    tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
    maxZoom: 19,
    canBeOverlay: true,
    defaultOpacity: 0.7,
  );
  MapSource yandex(String layer) => MapSource(
        id: 'yandex-$layer',
        name: 'Яндекс $layer',
        format: TileFormat.raster,
        storageMode: StorageMode.onlineOnly,
        tileUrlTemplate: 'https://tiles.api-maps.yandex.ru/v1/tiles/?x={x}&y={y}&z={z}&l=$layer',
        attribution: '© Яндекс',
        maxZoom: 21,
        canBeOverlay: true,
        defaultOpacity: 0.75,
        extraParams: {'layer': layer},
      );
  final ySat = yandex('sat');
  final yHybrid = yandex('skl');
  final yMap = yandex('map');
  const googleSat = MapSource(
    id: 'google-satellite',
    name: 'Google Satellite',
    format: TileFormat.raster,
    storageMode: StorageMode.onlineOnly,
    attribution: '© Google',
    extraParams: {'mapType': 'satellite'},
  );
  const vectorOverlay = MapSource(
    id: 'ofm-positron',
    name: 'Positron',
    format: TileFormat.vector,
    storageMode: StorageMode.onlineCache,
    styleUrl: 'https://x',
  );

  final catalogAll = LayerCatalog([
    MapProvider(id: 'osm', name: 'OSM', sources: const [liberty, osm, vectorOverlay]),
    const MapProvider(id: 'google', name: 'Google', isolated: true, sources: [googleSat]),
    MapProvider(id: 'yandex', name: 'Яндекс', sources: [ySat, yHybrid, yMap]),
  ]);

  late FakeHost host;
  late int yandexStatus;
  late String googleKey;

  LayerManager manager({int maxRasterOverlays = 3, LayerCatalog? catalog}) {
    host = FakeHost();
    return LayerManager(
      host: host,
      catalog: catalog ?? catalogAll,
      maxRasterOverlays: maxRasterOverlays,
      yandex: YandexTilesService(
        apiKey: 'YK',
        httpClient: MockClient((_) async => http.Response.bytes(const [1], yandexStatus)),
      ),
      google: GoogleTilesService(
        apiKey: googleKey,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('createSession')) {
            return http.Response(jsonEncode({'session': 'GS', 'expiry': '9999999999'}), 200);
          }
          return http.Response.bytes(const [1], 200);
        }),
      ),
    );
  }

  setUp(() {
    yandexStatus = 200;
    googleKey = 'GK';
  });

  group('base', () {
    test('a vector base loads its style URL', () async {
      final m = manager();
      final result = await m.setBaseSource(liberty);
      expect(result.ok, isTrue);
      expect(host.style, liberty.styleUrl);
      expect(m.base, liberty);
    });

    test('our hybrid base gets the phone-side road look; other vector bases keep theirs', () async {
      const hybrid = MapSource(
        id: 'server-hybrid-day',
        name: 'Спутник + дороги',
        format: TileFormat.vector,
        storageMode: StorageMode.onlineCache,
        styleUrl: 'https://192.168.1.120/tiles/style/hybrid-day',
      );
      final m = manager(catalog: LayerCatalog([const MapProvider(id: 'server', name: 'Сервер', sources: [hybrid, liberty])]));
      await m.setBaseSource(hybrid);
      expect(host.linePaints, hybridRoadPaint(hybrid.styleUrl!));
      expect(host.calls.indexOf('setStyle'), lessThan(host.calls.indexOf('linePaint road-major')));

      host.linePaints.clear();
      await m.setBaseSource(liberty);
      expect(host.linePaints, isEmpty);
    });

    test('a raster base becomes a one-source style with the keyed URL', () async {
      final m = manager();
      await m.setBaseSource(ySat);
      final style = jsonDecode(host.style!) as Map<String, dynamic>;
      final source = (style['sources'] as Map<String, dynamic>)['yandex-sat'] as Map<String, dynamic>;
      expect(source['type'], 'raster');
      expect(source['tiles'], ['https://tiles.api-maps.yandex.ru/v1/tiles/?x={x}&y={y}&z={z}&l=sat&apikey=YK']);
      expect(source['attribution'], '© Яндекс');
      expect(source['maxzoom'], 21);
      expect((style['layers'] as List).last, {'id': 'yandex-sat-layer', 'type': 'raster', 'source': 'yandex-sat'});
      expect(style['glyphs'], isNotNull, reason: 'annotation symbols may need fonts');
    });

    test('a local .mbtiles base is opened as a tileset URL with its own zoom range', () async {
      const local = MapSource(
        id: 'local-sat.mbtiles',
        name: 'sat',
        format: TileFormat.raster,
        storageMode: StorageMode.offlineRegion,
        tileUrlTemplate: 'mbtiles:///storage/maps/sat.mbtiles',
        canBeOverlay: true,
      );
      final m = manager(catalog: LayerCatalog([const MapProvider(id: 'local', name: 'Local', sources: [local])]));
      await m.setBaseSource(local);
      final style = jsonDecode(host.style!) as Map<String, dynamic>;
      final source = (style['sources'] as Map<String, dynamic>)['local-sat.mbtiles'] as Map<String, dynamic>;
      expect(source['url'], 'mbtiles:///storage/maps/sat.mbtiles');
      expect(source.containsKey('tiles'), isFalse);
      expect(source.containsKey('maxzoom'), isFalse, reason: 'MapLibre reads it from the file and overzooms');
    });

    test('a Google base uses the session URL', () async {
      final m = manager();
      await m.setBaseSource(googleSat);
      expect(host.style, contains('https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=GS&key=GK'));
    });

    test('a base that cannot be reached leaves the current map untouched', () async {
      googleKey = '';
      final m = manager();
      await m.setBaseSource(liberty);
      host.calls.clear();
      await expectLater(m.setBaseSource(googleSat), throwsA(isA<LayerException>()));
      expect(host.calls, isEmpty);
      expect(m.base, liberty);
    });
  });

  group('overlays', () {
    test('first overlay goes under the tracks, next ones above the previous', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      final first = await m.addOverlay(yHybrid);
      final second = await m.addOverlay(osm, opacity: 0.4);

      expect(first.zIndex, 10);
      expect(first.opacity, 0.75, reason: 'catalog default for Яндекс');
      expect(second.zIndex, 20);
      expect(host.calls, contains('addLayer yandex-skl-layer below lines_0'));
      expect(host.calls, contains('addLayer osm-standard-layer below lines_0'));
      expect(host.layers, ['yandex-skl-layer', 'osm-standard-layer']);
      expect(host.opacities['osm-standard-layer'], 0.4);
      expect(host.sources['yandex-skl'], endsWith('&apikey=YK'));
      expect(m.getActiveLayers().map((l) => l.sourceId), ['yandex-skl', 'osm-standard']);
    });

    test('nothing may be laid over a Google base, and Google is never an overlay', () async {
      final m = manager();
      await m.setBaseSource(googleSat);
      host.calls.clear();
      await expectLater(
        m.addOverlay(yHybrid),
        throwsA(isA<LayerException>().having((e) => e.message, 'message', contains('Google'))),
      );
      expect(host.calls, isEmpty);

      await m.setBaseSource(liberty);
      await expectLater(m.addOverlay(googleSat), throwsA(isA<LayerException>()));
    });

    test('vector sources and sources not marked canBeOverlay are refused', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await expectLater(m.addOverlay(vectorOverlay), throwsA(isA<LayerException>()));
    });

    test('the same source twice is refused', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.addOverlay(yHybrid);
      await expectLater(m.addOverlay(yHybrid), throwsA(isA<LayerException>()));
    });

    test('a failing Яндекс layer is refused with its message; other layers stay', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.addOverlay(osm);
      yandexStatus = 403;
      await expectLater(
        m.addOverlay(yHybrid),
        throwsA(isA<LayerException>().having((e) => e.message, 'message', YandexTilesService.forbiddenMessage)),
      );
      expect(host.layers, ['osm-standard-layer']);
      expect(m.getActiveLayers().map((l) => l.sourceId), ['osm-standard']);
    });

    test('at most maxRasterOverlays raster overlays', () async {
      final m = manager(maxRasterOverlays: 2);
      await m.setBaseSource(liberty);
      await m.addOverlay(yHybrid);
      await m.addOverlay(osm);
      await expectLater(
        m.addOverlay(yMap),
        throwsA(isA<LayerException>().having((e) => e.message, 'message', contains('2'))),
      );
    });

    test('opacity and visibility', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.addOverlay(yHybrid);

      await m.setOpacity('yandex-skl', 0.3);
      expect(host.opacities['yandex-skl-layer'], 0.3);
      await m.setVisibility('yandex-skl', false);
      expect(host.opacities['yandex-skl-layer'], 0.0);
      expect(m.getActiveLayers().single.visible, isFalse);
      expect(m.getActiveLayers().single.opacity, 0.3, reason: 'hiding keeps the chosen opacity');
      await m.setVisibility('yandex-skl', true);
      expect(host.opacities['yandex-skl-layer'], 0.3);

      await m.setVisibility('yandex-skl', false);
      await m.setOpacity('yandex-skl', 0.6);
      expect(host.opacities['yandex-skl-layer'], 0.0, reason: 'a hidden layer stays hidden');
    });

    test('remove', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.addOverlay(yHybrid);
      await m.removeOverlay('yandex-skl');
      expect(host.calls.sublist(host.calls.length - 2), ['removeLayer yandex-skl-layer', 'removeSource yandex-skl']);
      expect(m.getActiveLayers(), isEmpty);
    });

    test('reorder rebuilds the layers bottom → top in the given order', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.addOverlay(yHybrid);
      await m.addOverlay(osm);
      await m.addOverlay(yMap);

      await m.reorderOverlays(['yandex-map', 'yandex-skl', 'osm-standard']);
      expect(host.layers, ['yandex-map-layer', 'yandex-skl-layer', 'osm-standard-layer']);
      expect(m.getActiveLayers().map((l) => (l.sourceId, l.zIndex)), [
        ('yandex-map', 10),
        ('yandex-skl', 20),
        ('osm-standard', 30),
      ]);
    });
  });

  group('changing the base', () {
    test('overlays are restored in order with their opacity and visibility', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.addOverlay(yHybrid);
      await m.addOverlay(osm, opacity: 0.5);
      await m.setVisibility('osm-standard', false);

      final result = await m.setBaseSource(ySat);
      expect(result.ok, isTrue);
      expect(host.layers, ['yandex-skl-layer', 'osm-standard-layer']);
      expect(host.opacities['yandex-skl-layer'], 0.75);
      expect(host.opacities['osm-standard-layer'], 0.0);
      expect(m.getActiveLayers().map((l) => (l.sourceId, l.opacity, l.visible)), [
        ('yandex-skl', 0.75, true),
        ('osm-standard', 0.5, false),
      ]);
    });

    test('switching to Google drops the overlays and says so', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.addOverlay(yHybrid);
      final result = await m.setBaseSource(googleSat);
      expect(result.ok, isFalse);
      expect(result.problems.single, contains('Google'));
      expect(m.getActiveLayers(), isEmpty);
      expect(host.layers, isEmpty);
    });

    test('one overlay failing to come back does not stop the others', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.addOverlay(osm);
      await m.addOverlay(yHybrid);

      final fresh = manager();
      await fresh.setBaseSource(liberty);
      yandexStatus = 403;
      final result = await fresh.restoreOverlays(m.getActiveLayers());
      expect(result.problems.single, contains(YandexTilesService.forbiddenMessage));
      expect(fresh.getActiveLayers().map((l) => l.sourceId), ['osm-standard']);
    });
  });

  test('operations run one at a time: overlays added during a base change land on the new style', () async {
    final m = manager();
    await m.setBaseSource(liberty);
    host.styleGate = Completer<void>();
    final base = m.setBaseSource(ySat);
    final overlay = m.addOverlay(osm);
    await Future<void>.delayed(Duration.zero);
    expect(host.calls.last, 'setStyle', reason: 'addOverlay waits for the style change');
    host.styleGate!.complete();
    await base;
    await overlay;
    expect(host.layers, ['osm-standard-layer']);
  });

  group('orthophotos', () {
    MapSource ortho(String name) => MapSource(
          id: 'ortho-$name.mbtiles',
          name: name,
          format: TileFormat.raster,
          storageMode: StorageMode.offlineRegion,
          tileUrlTemplate: 'mbtiles:///o/$name.mbtiles',
          canBeOverlay: true,
        );
    final dobro = ortho('Доброполье');
    final avd = ortho('Авдеевка');
    final kram = ortho('Краматорск');
    final konst = ortho('Константиновка');

    test('any number of territories, not counted against the overlay limit', () async {
      final m = manager(maxRasterOverlays: 1);
      await m.setBaseSource(liberty);
      await m.addOverlay(osm);
      final result = await m.setOrthophotos([dobro, avd, kram, konst]);
      expect(result.ok, isTrue);
      expect(m.getOrthophotos(), hasLength(4));
      expect(host.sources['ortho-Доброполье.mbtiles'], 'mbtiles:///o/Доброполье.mbtiles');
      // Above the overlay.
      expect(host.layers.first, 'osm-standard-layer');
      expect(host.layers.skip(1), hasLength(4));
    });

    test('an empty list takes them off', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.setOrthophotos([dobro, avd]);
      await m.setOrthophotos(const []);
      expect(m.getOrthophotos(), isEmpty);
      expect(host.layers, isEmpty);
      expect(host.sources, isEmpty);
    });

    test('they go under the base style roads, so the roads stay visible', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      host.styleLayers = ['background', 'satellite', 'road-middle-casing', 'road-major', 'boundary-country'];
      await m.setOrthophotos([dobro, avd]);
      expect(host.calls, contains('addLayer ortho-Доброполье.mbtiles-layer below road-middle-casing'));
      expect(host.calls, contains('addLayer ortho-Авдеевка.mbtiles-layer below road-middle-casing'));
    });

    test('a base without roads: under the annotations', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      host.styleLayers = ['background', 'satellite'];
      await m.setOrthophotos([dobro]);
      expect(host.calls, contains('addLayer ortho-Доброполье.mbtiles-layer below lines_0'));
    });

    test('a new overlay goes under the orthophotos', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.setOrthophotos([dobro]);
      await m.addOverlay(osm);
      expect(host.layers, ['osm-standard-layer', 'ortho-Доброполье.mbtiles-layer']);
    });

    test('they survive a base change and stay above the overlays', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.addOverlay(osm);
      await m.setOrthophotos([dobro, avd]);
      final result = await m.setBaseSource(ySat);
      expect(result.ok, isTrue);
      expect(m.getOrthophotos().map((s) => s.id), [dobro.id, avd.id]);
      expect(host.layers.first, 'osm-standard-layer');
      expect(host.layers.skip(1).toSet(), {'ortho-Доброполье.mbtiles-layer', 'ortho-Авдеевка.mbtiles-layer'});
    });

    test('one shown as the base or as an overlay is not added twice', () async {
      final m = manager();
      await m.setBaseSource(dobro);
      await m.setOrthophotos([dobro, avd]);
      expect(m.getOrthophotos().map((s) => s.id), [avd.id]);
      await expectLater(m.addOverlay(avd), throwsA(isA<LayerException>()));
    });

    test('over an isolated base they are not shown', () async {
      final m = manager();
      await m.setBaseSource(googleSat);
      final result = await m.setOrthophotos([dobro]);
      expect(result.ok, isFalse);
      expect(m.getOrthophotos(), isEmpty);
    });
  });

  group('colour', () {
    test('settings map to MapLibre raster paint; inversion swaps the brightness range', () {
      expect(RasterColor.of(const LayerColorSettings()), RasterColor.none);
      expect(
        RasterColor.of(const LayerColorSettings(brightness: 0.25, contrast: 1.5, saturation: 0)),
        const RasterColor(brightnessMin: 0.25, brightnessMax: 1, contrast: 0.5, saturation: -1),
      );
      expect(
        RasterColor.of(const LayerColorSettings(brightness: -0.25, inverted: true)),
        const RasterColor(brightnessMin: 0.75, brightnessMax: 0),
      );
    });

    test('goes with every opacity change, survives reordering and is dropped on removal', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.addOverlay(osm);
      await m.addOverlay(yHybrid);
      const inverted = LayerColorSettings(inverted: true);
      final invertedPaint = RasterColor.of(inverted);
      await m.setColor(osm.id, inverted);
      expect(host.colors['osm-standard-layer'], invertedPaint);

      await m.setOpacity(osm.id, 0.4);
      expect(host.colors['osm-standard-layer'], invertedPaint);
      await m.reorderOverlays([yHybrid.id, osm.id]);
      expect(host.colors['osm-standard-layer'], invertedPaint);
      expect(host.colors[LayerManager.layerIdOf(yHybrid.id)], RasterColor.none);

      await m.removeOverlay(osm.id);
      await m.addOverlay(osm);
      expect(host.colors['osm-standard-layer'], RasterColor.none);
    });

    test('set before the overlay is added, it applies when it is added', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.setColor(osm.id, const LayerColorSettings(saturation: 0));
      await m.addOverlay(osm);
      expect(host.colors['osm-standard-layer']!.saturation, -1);
    });
  });

  group('world base map', () {
    test('goes right above the style background on every base change; not under an isolated base', () async {
      final m = manager();
      host.styleLayers = ['background', 'water', 'road-main'];
      await m.setWorld('/data/base/world.mbtiles');
      expect(host.sources, isEmpty, reason: 'no map yet');

      await m.setBaseSource(liberty);
      expect(host.sources[LayerManager.worldSourceId], 'mbtiles:///data/base/world.mbtiles');
      expect(host.calls, contains('addLayer ${LayerManager.layerIdOf(LayerManager.worldSourceId)} below water'));

      await m.setBaseSource(ySat);
      expect(host.sources.keys, contains(LayerManager.worldSourceId), reason: 'put back on the new style');

      await m.setBaseSource(googleSat);
      expect(host.sources.keys, isNot(contains(LayerManager.worldSourceId)));
    });

    test('opacity is kept and applied', () async {
      final m = manager();
      host.styleLayers = ['background'];
      await m.setWorld('/w.mbtiles', opacity: 0.4);
      await m.setBaseSource(liberty);
      final layer = LayerManager.layerIdOf(LayerManager.worldSourceId);
      expect(host.opacities[layer], 0.4);
      await m.setWorldOpacity(0.8);
      expect(host.opacities[layer], 0.8);
    });

    test('hiding the map hides its style layers but the background; it stays hidden on a base change', () async {
      final m = manager();
      host.styleLayers = ['background', 'water', 'road-main'];
      await m.setWorld('/w.mbtiles');
      await m.setBaseSource(liberty);
      await m.addOverlay(osm);
      await m.setMapVisible(false);
      expect(host.hidden, {'water', 'road-main'});
      expect(m.mapVisible, isFalse);

      host.hidden.clear();
      await m.setBaseSource(ySat);
      expect(host.hidden, {'water', 'road-main'}, reason: 'the new style is hidden too');
      expect(host.hidden, isNot(contains(LayerManager.layerIdOf(osm.id))));
      expect(host.hidden, isNot(contains(LayerManager.layerIdOf(LayerManager.worldSourceId))));

      await m.setMapVisible(true);
      expect(host.hidden, isEmpty);
    });

    test('without a file nothing is added', () async {
      final m = manager();
      await m.setWorld(null);
      await m.setBaseSource(liberty);
      expect(host.sources.keys, isNot(contains(LayerManager.worldSourceId)));
    });
  });

  group('overlays under the map', () {
    test('the lowest ones go under the map\'s own layers, the rest above it; kept on a base change', () async {
      final m = manager();
      host.styleLayers = ['background', 'map-fill', 'road-main'];
      await m.setBaseSource(liberty);
      await m.addOverlay(osm);
      await m.addOverlay(yHybrid);
      await m.reorderOverlays([osm.id, yHybrid.id], underMap: 1);
      expect(m.overlaysUnderMap, 1);
      expect(host.calls, contains('addLayer ${LayerManager.layerIdOf(osm.id)} below map-fill'));
      expect(host.calls, contains('addLayer ${LayerManager.layerIdOf(yHybrid.id)} below lines_0'));

      host.calls.clear();
      await m.setBaseSource(liberty);
      expect(host.calls, contains('addLayer ${LayerManager.layerIdOf(osm.id)} below map-fill'));

      await m.removeOverlay(osm.id);
      expect(m.overlaysUnderMap, 0);
    });

    test('force refresh marks the saved tiles stale', () async {
      final m = manager();
      await m.setBaseSource(liberty);
      await m.refreshTiles();
      expect(host.calls.last, 'invalidateCache');
    });
  });

  group('chosen map paint', () {
    test('a raster map: opacity and colour on its one layer; reset for another map', () async {
      final m = manager();
      await m.setBaseSource(ySat);
      await m.setMapPaint(opacity: 0.5, color: const LayerColorSettings(saturation: 0));
      final layer = LayerManager.layerIdOf(ySat.id);
      expect(host.opacities[layer], 0.5);
      expect(host.colors[layer]!.saturation, -1);
      host.calls.clear();
      await m.setBaseSource(yHybrid);
      expect(host.calls.where((c) => c.startsWith('opacity ')), isEmpty, reason: 'a new map starts as is');
    });
  });

  group('vector overlay', () {
    const roads = MapSource(
      id: 'server-roads',
      name: 'Дороги',
      styleUrl: 'https://t/style/hybrid-day',
      format: TileFormat.vector,
      storageMode: StorageMode.onlineCache,
      canBeOverlay: true,
    );

    LayerManager vectorManager() => LayerManager(
          host: host,
          catalog: LayerCatalog([
            const MapProvider(id: 'osm', name: 'OSM', sources: [liberty, osm]),
            const MapProvider(id: 'server-layers', name: 'Слои', sources: [roads]),
          ]),
          google: GoogleTilesService(apiKey: '', httpClient: MockClient((_) async => http.Response('', 500))),
          yandex: YandexTilesService(apiKey: '', httpClient: MockClient((_) async => http.Response('', 500))),
          fetchText: (url) async {
            expect(url.toString(), 'https://t/style/hybrid-day');
            return convert.jsonEncode(hybridStyle);
          },
        );

    test('lays its roads and labels under the annotations, without its background and imagery', () async {
      final m = vectorManager();
      await m.setBaseSource(liberty);
      await m.addOverlay(roads);
      expect(host.sources.keys, contains('server-roads~osm'));
      expect(host.sources.keys, isNot(contains('server-roads~satellite')));
      expect(host.layers, ['server-roads~building', 'server-roads~road-main', 'server-roads~place-label']);
      expect(host.calls, contains('addStyleLayer server-roads~road-main below lines_0'));
      expect(m.getActiveLayers().single.sourceId, 'server-roads');
    });

    test('opacity scales each layer; the eye hides them; removing takes all of it away', () async {
      final m = vectorManager();
      await m.setBaseSource(liberty);
      await m.addOverlay(roads);
      await m.setOpacity(roads.id, 0.5);
      expect((host.styleLayers_['server-roads~building']!['paint'] as Map)['fill-opacity'], 0.25);
      await m.setVisibility(roads.id, false);
      expect(host.hidden, {'server-roads~building', 'server-roads~road-main', 'server-roads~place-label'});
      await m.removeOverlay(roads.id);
      expect(host.layers, isEmpty);
      expect(host.sources.keys, isNot(contains('server-roads~osm')));
    });

    test('reorders with raster overlays and comes back after a base change', () async {
      final m = vectorManager();
      await m.setBaseSource(liberty);
      await m.addOverlay(roads);
      await m.addOverlay(osm);
      expect(host.layers.last, LayerManager.layerIdOf(osm.id));
      await m.reorderOverlays([osm.id, roads.id]);
      expect(host.layers.first, LayerManager.layerIdOf(osm.id));
      expect(host.layers.last, 'server-roads~place-label');

      await m.setBaseSource(liberty);
      expect(host.layers.first, LayerManager.layerIdOf(osm.id));
      expect(host.layers.last, 'server-roads~place-label');
    });
  });
}
