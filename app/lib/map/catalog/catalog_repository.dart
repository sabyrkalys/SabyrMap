import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../mediafile/mediafile_folder_service.dart';
import '../../mediafile/mediafile_subfolders.dart';
import '../models/map_models.dart';

class CatalogException implements Exception {
  const CatalogException(this.message);

  final String message;

  @override
  String toString() => 'CatalogException: $message';
}

/// The list of map providers and their sources: the catalog bundled in
/// assets (or a newer one fetched with [refreshFromUrl]), plus the user's
/// local .mbtiles files from mediafile/maps.
class CatalogRepository {
  CatalogRepository({MediaFileFolderService? mapsFolder, http.Client? httpClient, AssetBundle? bundle})
      : _mapsFolder = mapsFolder ?? MediaFileFolderService(subfolder: kMapsSubfolder),
        _http = httpClient ?? http.Client(),
        _bundle = bundle ?? rootBundle;

  static const String builtinAsset = 'assets/maps/builtin_catalog.json';
  static const String localProviderId = 'local';

  final MediaFileFolderService _mapsFolder;
  final http.Client _http;
  final AssetBundle _bundle;

  /// Set by a successful [refreshFromUrl]; replaces the built-in providers.
  List<MapProvider>? _remote;

  static List<MapProvider> parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw CatalogException('Каталог карт повреждён: ${e.message}');
    }
    if (decoded is! Map<String, dynamic> || decoded['providers'] is! List) {
      throw const CatalogException('Каталог карт повреждён: нет списка providers');
    }
    try {
      return [
        for (final p in decoded['providers'] as List<dynamic>) MapProvider.fromJson(p as Map<String, dynamic>),
      ];
    } on FormatException catch (e) {
      throw CatalogException('Каталог карт повреждён: ${e.message}');
    } on TypeError catch (e) {
      throw CatalogException('Каталог карт повреждён: $e');
    }
  }

  Future<List<MapProvider>> loadBuiltin() async => parse(await _bundle.loadString(builtinAsset));

  /// Built-in (or refreshed) providers followed by «Установленные карты»
  /// when mediafile/maps holds .mbtiles files.
  Future<List<MapProvider>> load() async {
    final providers = _remote ?? await loadBuiltin();
    final local = await _localSources();
    return [
      ...providers,
      if (local.isNotEmpty) MapProvider(id: localProviderId, name: 'Установленные карты', sources: local),
    ];
  }

  /// Fetches a catalog JSON from [url]. On success it replaces the built-in
  /// providers for later [load]s; on any failure the current catalog stays
  /// and a [CatalogException] is thrown.
  Future<List<MapProvider>> refreshFromUrl(Uri url) async {
    final http.Response response;
    try {
      response = await _http.get(url);
    } catch (e) {
      throw CatalogException('Не удалось загрузить каталог карт: $e');
    }
    if (response.statusCode != 200) {
      throw CatalogException('Не удалось загрузить каталог карт: HTTP ${response.statusCode}');
    }
    final providers = parse(utf8.decode(response.bodyBytes));
    _remote = providers;
    return providers;
  }

  Future<List<MapSource>> _localSources() async {
    final entries = await _mapsFolder.list();
    return [
      for (final entry in entries)
        if (entry.fileName.toLowerCase().endsWith('.mbtiles'))
          MapSource(
            id: 'local-${entry.fileName}',
            name: entry.fileName.substring(0, entry.fileName.length - '.mbtiles'.length),
            // Raster until the file's metadata is read (a later block);
            // MapLibre opens .mbtiles through the mbtiles:// scheme.
            tileUrlTemplate: 'mbtiles://${entry.path}',
            format: TileFormat.raster,
            storageMode: StorageMode.offlineRegion,
            canBeOverlay: true,
          ),
    ];
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => CatalogRepository());

/// The current catalog; [refresh] pulls a newer one from a URL.
class CatalogNotifier extends AsyncNotifier<List<MapProvider>> {
  @override
  Future<List<MapProvider>> build() => ref.read(catalogRepositoryProvider).load();

  Future<void> refresh(Uri url) async {
    final repository = ref.read(catalogRepositoryProvider);
    await repository.refreshFromUrl(url);
    state = AsyncData(await repository.load());
  }

  /// Re-reads local files, e.g. after a .mbtiles import.
  Future<void> reload() async => state = AsyncData(await ref.read(catalogRepositoryProvider).load());
}

final catalogProvider = AsyncNotifierProvider<CatalogNotifier, List<MapProvider>>(CatalogNotifier.new);
