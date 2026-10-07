import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path_provider/path_provider.dart';

import '../catalog/catalog_repository.dart';
import '../models/map_models.dart';
import '../state/map_viewport.dart';
import 'google_tiles_service.dart';
import 'layer_manager.dart';
import 'yandex_tiles_service.dart';

/// Draws a map style off screen (MainActivity's `sabyrmap/map_preview`
/// channel over MapLibre's MapSnapshotter). Null when it can't.
abstract class MapPreviewRenderer {
  /// JPEG of [style] (a URL or style JSON) around [center]; [width] and
  /// [height] in logical pixels.
  Future<Uint8List?> render({
    required String style,
    required LatLng center,
    required double zoom,
    required int width,
    required int height,
  });
}

class PlatformMapPreviewRenderer implements MapPreviewRenderer {
  const PlatformMapPreviewRenderer();

  static const _channel = MethodChannel('sabyrmap/map_preview');

  @override
  Future<Uint8List?> render({
    required String style,
    required LatLng center,
    required double zoom,
    required int width,
    required int height,
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>('snapshot', {
        'style': style,
        'lat': center.latitude,
        'lng': center.longitude,
        'zoom': zoom,
        'width': width,
        'height': height,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Card pictures of maps, kept as files: each map is drawn once, around
/// wherever the map was then, and its picture is never redrawn. Drawn one
/// at a time, as every snapshot is a whole off-screen map.
class MapPreviews {
  MapPreviews({required MapPreviewRenderer renderer, required Future<Directory> Function() directory})
      : _renderer = renderer,
        _directory = directory;

  static const double zoom = 12;

  /// Logical size; the card is 96 px high and as wide as the screen.
  static const int width = 480;
  static const int height = 120;

  final MapPreviewRenderer _renderer;
  final Future<Directory> Function() _directory;
  Future<void> _tail = Future.value();

  Future<File> _fileOf(MapSource source) async {
    final name = sha1.convert(utf8.encode(source.id)).toString().substring(0, 16);
    return File('${(await _directory()).path}/$name.jpg');
  }

  /// The picture of [source] drawn before, or null.
  Future<File?> saved(MapSource source) async {
    final file = await _fileOf(source);
    return file.existsSync() ? file : null;
  }

  /// [saved], or [source] drawn now with [style] around [center]. Null when
  /// it can't be drawn; it is tried again next time.
  Future<File?> draw(MapSource source, String style, LatLng center) async {
    final file = await _fileOf(source);
    if (file.existsSync()) return file;
    return _serial(() async {
      if (file.existsSync()) return file;
      final bytes = await _renderer.render(
        style: style,
        center: center,
        zoom: zoom.clamp(source.minZoom.toDouble(), source.maxZoom.toDouble()),
        width: width,
        height: height,
      );
      if (bytes == null || bytes.isEmpty) return null;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    });
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

final mapPreviewsProvider = Provider<MapPreviews>((ref) => MapPreviews(
      renderer: const PlatformMapPreviewRenderer(),
      directory: () async => Directory('${(await getApplicationSupportDirectory()).path}/map_previews'),
    ));

/// The card picture of [source]: the saved one, or drawn now around the
/// map's current center; null while there is none and the map isn't open
/// or the style can't be drawn.
final mapPreviewProvider = FutureProvider.autoDispose.family<File?, MapSource>((ref, source) async {
  final previews = ref.read(mapPreviewsProvider);
  try {
    final saved = await previews.saved(source);
    if (saved != null) return saved;
    final viewport = await ref.read(mapViewportProvider.notifier).read();
    if (viewport == null) return null;
    final bounds = viewport.bounds;
    final center = LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
    final providers = await ref.watch(catalogProvider.future);
    final styles = MapStyleResolver(
      catalog: LayerCatalog(providers),
      google: ref.read(googleTilesServiceProvider),
      yandex: ref.read(yandexTilesServiceProvider),
    );
    return await previews.draw(source, await styles.styleOf(source), center);
  } on LayerException {
    return null;
  } on FileSystemException {
    return null;
  }
});
