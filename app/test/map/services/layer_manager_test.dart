import 'dart:async';
import 'dart:convert';

import 'package:app/map/models/map_models.dart';
import 'package:app/map/services/google_tiles_service.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/services/yandex_tiles_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records every call the manager makes on the map.
class FakeHost implements MapLayerHost {
  final calls = <String>[];
  final sources = <String, String>{}; // id → tile URL
  final layers = <String>[]; // bottom → top, overlay layers only
  final opacities = <String, double>{};
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
  Future<void> addRasterLayer(String sourceId, String layerId, {required double opacity, String? belowLayerId}) async {
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
  Future<void> setRasterOpacity(String layerId, double opacity) async {
    calls.add('opacity $layerId $opacity');
    opacities[layerId] = opacity;
  }
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

  final catalog = LayerCatalog([
    MapProvider(id: 'osm', name: 'OSM', sources: const [liberty, osm, vectorOverlay]),
    const MapProvider(id: 'google', name: 'Google', isolated: true, sources: [googleSat]),
    MapProvider(id: 'yandex', name: 'Яндекс', sources: [ySat, yHybrid, yMap]),
  ]);

  late FakeHost host;
  late int yandexStatus;
  late String googleKey;

  LayerManager manager({int maxRasterOverlays = 3}) {
    host = FakeHost();
    return LayerManager(
      host: host,
      catalog: catalog,
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
}
