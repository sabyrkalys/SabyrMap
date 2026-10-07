import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/map/models/map_models.dart';
import 'package:app/map/services/map_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class _FakeRenderer implements MapPreviewRenderer {
  final calls = <({String style, LatLng center, double zoom})>[];
  Uint8List? Function() answer = () => Uint8List.fromList([1, 2, 3]);
  Completer<void>? gate;

  @override
  Future<Uint8List?> render({
    required String style,
    required LatLng center,
    required double zoom,
    required int width,
    required int height,
  }) async {
    calls.add((style: style, center: center, zoom: zoom));
    await gate?.future;
    return answer();
  }
}

const _source = MapSource(
  id: 'server-satellite',
  name: 'Спутник',
  format: TileFormat.raster,
  storageMode: StorageMode.onlineCache,
  maxZoom: 17,
);

void main() {
  late Directory dir;
  late _FakeRenderer renderer;
  late MapPreviews previews;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('map_previews_test');
    renderer = _FakeRenderer();
    previews = MapPreviews(renderer: renderer, directory: () async => dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  List<String> files() => [for (final f in dir.listSync()) f.uri.pathSegments.last];

  test('draws a map once and never again, wherever the map moves or whatever its style', () async {
    expect(await previews.saved(_source), isNull);
    final first = await previews.draw(_source, 'style-a', const LatLng(42.87, 74.59));
    final moved = await previews.draw(_source, 'style-b', const LatLng(50.45, 30.52));

    expect(first!.readAsBytesSync(), [1, 2, 3]);
    expect(moved!.path, first.path);
    expect((await previews.saved(_source))!.path, first.path);
    expect(renderer.calls, hasLength(1));
    expect(renderer.calls.single.style, 'style-a');
    expect(renderer.calls.single.center, const LatLng(42.87, 74.59));
    expect(renderer.calls.single.zoom, MapPreviews.zoom);
    expect(files(), hasLength(1));
  });

  test('keeps the zoom inside the map\'s zoom range', () async {
    const lowZoomMap = MapSource(
      id: 'overview',
      name: 'Обзорная',
      format: TileFormat.raster,
      storageMode: StorageMode.onlineCache,
      maxZoom: 8,
    );
    await previews.draw(lowZoomMap, 'style', const LatLng(42.87, 74.59));

    expect(renderer.calls.single.zoom, 8);
  });

  test('a map that could not be drawn has no preview and is tried again later', () async {
    renderer.answer = () => null;
    expect(await previews.draw(_source, 'style-a', const LatLng(42.87, 74.59)), isNull);
    expect(files(), isEmpty);

    renderer.answer = () => Uint8List.fromList([7]);
    expect(await previews.draw(_source, 'style-a', const LatLng(42.87, 74.59)), isNotNull);
    expect(renderer.calls, hasLength(2));
  });

  test('draws one map at a time and does not draw the same one twice', () async {
    renderer.gate = Completer<void>();
    const other = MapSource(id: 'other', name: 'Другая', format: TileFormat.vector, storageMode: StorageMode.onlineCache);
    final a = previews.draw(_source, 'style-a', const LatLng(42.87, 74.59));
    final b = previews.draw(other, 'style-o', const LatLng(42.87, 74.59));
    final aAgain = previews.draw(_source, 'style-a', const LatLng(42.87, 74.59));
    await pumpEventQueue();

    expect(renderer.calls, hasLength(1));
    renderer.gate!.complete();
    await Future.wait([a, b, aAgain]);
    expect(renderer.calls.map((c) => c.style), ['style-a', 'style-o']);
    expect((await aAgain)!.path, (await a)!.path);
  });
}
