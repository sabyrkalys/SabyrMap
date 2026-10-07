import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_repository.dart';
import '../models/map_models.dart';

/// MapLibre's tile cache as the app can see it (MainActivity's
/// `sabyrmap/tile_cache` channel over files/mbgl-offline.db).
abstract class TileCacheReader {
  /// Bytes per tile URL template; empty when unknown.
  Future<Map<String, int>> bytesByTemplate();

  /// The cached body of a style or TileJSON [url], null when not cached.
  Future<String?> resource(String url);
}

class PlatformTileCacheReader implements TileCacheReader {
  const PlatformTileCacheReader();

  static const _channel = MethodChannel('sabyrmap/tile_cache');

  @override
  Future<Map<String, int>> bytesByTemplate() async {
    try {
      final raw = await _channel.invokeMapMethod<String, int>('bytesByTemplate');
      return raw ?? const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  @override
  Future<String?> resource(String url) async {
    try {
      return await _channel.invokeMethod<String>('resource', {'url': url});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Which tile sets each map draws from, and how much of each is cached.
/// Maps share tile sets (every server style uses the same satellite), so
/// [bytesOf] counts each tile set once for any group of maps.
class TileCacheStats {
  const TileCacheStats({required this.templatesBySource, required this.bytesByTemplate});

  static const empty = TileCacheStats(templatesBySource: {}, bytesByTemplate: {});

  final Map<String, Set<String>> templatesBySource;
  final Map<String, int> bytesByTemplate;

  int bytesOf(Iterable<String> sourceIds) {
    final templates = {for (final id in sourceIds) ...?templatesBySource[id]};
    return templates.fold(0, (sum, t) => sum + (bytesByTemplate[t] ?? 0));
  }

  static Future<TileCacheStats> read(TileCacheReader reader, Iterable<MapSource> sources) async {
    final bytes = await reader.bytesByTemplate();
    if (bytes.isEmpty) return empty;
    final templates = <String, Set<String>>{};
    for (final source in sources) {
      final found = await _templatesOf(reader, source);
      if (found.isNotEmpty) templates[source.id] = found;
    }
    return TileCacheStats(templatesBySource: templates, bytesByTemplate: bytes);
  }

  /// A raster map's own template; for a vector map, the tile templates of
  /// its style's sources, read from the cached style (and TileJSON) so this
  /// works offline. Unknown (not cached, unreadable) gives nothing.
  static Future<Set<String>> _templatesOf(TileCacheReader reader, MapSource source) async {
    final raster = source.tileUrlTemplate;
    if (raster != null) return raster.startsWith('mbtiles://') ? const {} : {raster};
    final styleUrl = source.styleUrl;
    if (styleUrl == null) return const {};
    final styleJson = styleUrl.trimLeft().startsWith('{') ? styleUrl : await reader.resource(styleUrl);
    final style = _decode(styleJson);
    final styleSources = style?['sources'];
    if (styleSources is! Map) return const {};
    final found = <String>{};
    for (final entry in styleSources.values) {
      if (entry is! Map) continue;
      var tiles = entry['tiles'];
      final url = entry['url'];
      if (tiles is! List && url is String) tiles = _decode(await reader.resource(url))?['tiles'];
      if (tiles is List) found.addAll(tiles.whereType<String>());
    }
    return found;
  }

  static Map<String, dynamic>? _decode(String? json) {
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

final tileCacheReaderProvider = Provider<TileCacheReader>((ref) => const PlatformTileCacheReader());

/// [TileCacheStats] of the catalog's maps, re-read each time a screen
/// starts watching it (the cache grows as the map is used).
final tileCacheStatsProvider = FutureProvider.autoDispose<TileCacheStats>((ref) async {
  final providers = await ref.watch(catalogProvider.future);
  return TileCacheStats.read(ref.read(tileCacheReaderProvider), [for (final p in providers) ...p.sources]);
});
