import 'dart:async';
import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../config.dart';
import '../../mediafile/mediafile_folder_service.dart';
import '../../mediafile/mediafile_subfolders.dart';
import '../models/map_models.dart';

class CatalogException implements Exception {
  const CatalogException(this.message);

  final String message;

  @override
  String toString() => 'CatalogException: $message';
}

/// Style URLs the user added with «+»; kept on the device.
abstract class UserSourcesStore {
  Future<List<MapSource>> load();
  Future<void> save(List<MapSource> sources);
}

class SecureUserSourcesStore implements UserSourcesStore {
  SecureUserSourcesStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const String storageKey = 'user_map_sources';

  final FlutterSecureStorage _storage;

  @override
  Future<List<MapSource>> load() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return [];
    try {
      return [for (final s in jsonDecode(raw) as List<dynamic>) MapSource.fromJson(s as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<MapSource> sources) =>
      _storage.write(key: storageKey, value: jsonEncode([for (final s in sources) s.toJson()]));
}

/// The list of map providers and their sources: the catalog bundled in
/// assets (or a newer one fetched with [refreshFromUrl]), plus the user's
/// local files from mediafile/maps (.mbtiles, .json styles) and style URLs
/// the user added — the last two under «Установленные карты».
class CatalogRepository {
  CatalogRepository({
    MediaFileFolderService? mapsFolder,
    http.Client? httpClient,
    AssetBundle? bundle,
    UserSourcesStore? userSources,
    FileSystem? fileSystem,
    String? mapServerBaseUrl,
    this.catalogUrl,
    this.hiddenProviderIds = AppConfig.hiddenMapProviders,
  })  : _mapsFolder = mapsFolder ?? MediaFileFolderService(subfolder: kMapsSubfolder),
        _http = httpClient ?? http.Client(),
        _bundle = bundle ?? rootBundle,
        _userSources = userSources ?? SecureUserSourcesStore(),
        _fileSystem = fileSystem ?? const LocalFileSystem(),
        _mapServerBaseUrl = mapServerBaseUrl ?? AppConfig.mapServerBaseUrl;

  static const String builtinAsset = 'assets/maps/builtin_catalog.json';
  static const String localProviderId = 'local';
  static const String serverProviderId = 'server';
  static const String serverHybridSourceId = 'server-hybrid-day';
  static const String serverSatelliteSourceId = 'server-satellite';

  /// Base map shown when the user has not chosen one yet (or the saved one
  /// is gone from the catalog).
  static const String defaultBaseSourceId = serverHybridSourceId;

  final MediaFileFolderService _mapsFolder;
  final http.Client _http;
  final AssetBundle _bundle;
  final UserSourcesStore _userSources;
  final FileSystem _fileSystem;
  final String _mapServerBaseUrl;

  /// Our server's catalog (GET /maps), fetched in the background when the
  /// catalog is first loaded; null = no automatic refresh (tests).
  final Uri? catalogUrl;

  /// Providers left out of [load] (see AppConfig.hiddenMapProviders).
  final Set<String> hiddenProviderIds;

  /// Set by a successful [refreshFromUrl]; replaces the built-in providers
  /// with the same ids.
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

  /// Our own tile server («Сервер карт») as the app knows it without the
  /// server's catalog: same ids as GET /maps, so a saved choice still works
  /// offline or before the catalog arrives. Styles are published by the
  /// server (tools/build/publish_styles.sh) and served by Martin.
  MapProvider _serverProvider() {
    final base = _mapServerBaseUrl;
    MapSource style(String id, String name, String style) => MapSource(
          id: id,
          name: name,
          styleUrl: '$base/style/$style',
          format: TileFormat.vector,
          storageMode: StorageMode.onlineCache,
          minZoom: 0,
          maxZoom: 20,
          downloadable: true,
        );
    return MapProvider(
      id: serverProviderId,
      name: 'Сервер карт',
      sources: [
        style(serverHybridSourceId, 'Спутник + дороги', 'hybrid-day'),
        style('server-hybrid-night', 'Ночь', 'hybrid-night'),
        style('server-vector-day', 'Только дороги', 'vector-day'),
        style('server-vector-night', 'Только дороги (ночь)', 'vector-night'),
        MapSource(
          id: serverSatelliteSourceId,
          name: 'Спутник',
          tileUrlTemplate: '$base/satellite/{z}/{x}/{y}',
          format: TileFormat.raster,
          storageMode: StorageMode.onlineCache,
          minZoom: 0,
          maxZoom: 17,
          canBeOverlay: true,
          downloadable: true,
        ),
      ],
    );
  }

  /// The server's providers (or the built-in «Сервер карт» until its
  /// catalog arrived), the other built-in providers, then «Установленные
  /// карты» when mediafile/maps has files.
  Future<List<MapProvider>> load() async {
    final remote = _remote ?? const <MapProvider>[];
    final remoteIds = {for (final p in remote) p.id};
    final providers = [
      if (!remoteIds.contains(serverProviderId)) _serverProvider(),
      for (final p in [...remote, ...(await loadBuiltin()).where((p) => !remoteIds.contains(p.id))])
        if (!hiddenProviderIds.contains(p.id)) p,
    ];
    final local = [...await _localSources(), ...await _userSources.load()];
    return [
      ...providers,
      if (local.isNotEmpty) MapProvider(id: localProviderId, name: 'Установленные карты', sources: local),
    ];
  }

  /// Fetches a catalog JSON from [url]. On success its providers replace the
  /// built-in ones with the same ids for later [load]s; on any failure the
  /// current catalog stays and a [CatalogException] is thrown.
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

  /// Adds a vector style by URL («+» → Style URL).
  Future<MapSource> addStyleUrl({required String name, required String url}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      throw const CatalogException('Нужна ссылка вида https://…');
    }
    final source = MapSource(
      id: 'user-url-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? uri.host : name.trim(),
      styleUrl: uri.toString(),
      format: TileFormat.vector,
      storageMode: StorageMode.onlineCache,
    );
    await _userSources.save([...await _userSources.load(), source]);
    return source;
  }

  Future<void> removeUserSource(String id) async =>
      _userSources.save([for (final s in await _userSources.load()) if (s.id != id) s]);

  /// Copies a MapLibre style JSON file into mediafile/maps («+» → JSON-файл).
  Future<void> importStyleFile(String path) async {
    final String content;
    try {
      content = await _fileSystem.file(path).readAsString();
    } catch (e) {
      throw CatalogException('Не удалось прочитать файл: $e');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic> || decoded['version'] == null || decoded['layers'] is! List) {
      throw const CatalogException('Файл не похож на стиль MapLibre');
    }
    await _mapsFolder.importFile(path);
  }

  static const String localRegionPrefix = 'local-dir-';

  /// Deletes an offline region folder (a [localRegionPrefix] source).
  Future<void> deleteLocalRegion(String sourceId) async {
    if (!sourceId.startsWith(localRegionPrefix)) return;
    await _mapsFolder.deleteDirectory(sourceId.substring(localRegionPrefix.length));
  }

  /// An offline region folder (downloaded from our server): style.json +
  /// MBTiles is one vector map; MBTiles alone is a raster map. Folders still
  /// downloading (no style yet, only .part files) are skipped.
  Future<MapSource?> _regionSource(Directory dir) async {
    final name = dir.basename;
    String? attribution;
    final manifest = dir.childFile('manifest.json');
    if (manifest.existsSync()) {
      try {
        attribution = (jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>)['attribution'] as String?;
      } catch (_) {}
    }
    final style = dir.childFile('style.json');
    if (style.existsSync()) {
      return MapSource(
        id: '$localRegionPrefix$name',
        name: name,
        styleUrl: await style.readAsString(),
        format: TileFormat.vector,
        storageMode: StorageMode.offlineRegion,
        attribution: attribution,
      );
    }
    if (dir.childFile('style.zip').existsSync() || dir.childFile('style.zip.part').existsSync()) return null;
    final tiles = dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.mbtiles')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (tiles.isEmpty) return null;
    return MapSource(
      id: '$localRegionPrefix$name',
      name: name,
      tileUrlTemplate: 'mbtiles://${tiles.first.path}',
      format: TileFormat.raster,
      storageMode: StorageMode.offlineRegion,
      attribution: attribution,
      canBeOverlay: true,
    );
  }

  Future<List<MapSource>> _localSources() async {
    final entries = await _mapsFolder.list();
    return [
      for (final dir in await _mapsFolder.listDirectories())
        if (await _regionSource(dir) case final source?) source,
      for (final entry in entries)
        if (entry.fileName.toLowerCase().endsWith('.json'))
          MapSource(
            id: 'local-${entry.fileName}',
            name: entry.fileName.substring(0, entry.fileName.length - '.json'.length),
            // The style JSON itself: MapLibre's setStyle takes a URL or JSON.
            styleUrl: await _fileSystem.file(entry.path).readAsString(),
            format: TileFormat.vector,
            storageMode: StorageMode.offlineRegion,
          )
        else if (entry.fileName.toLowerCase().endsWith('.mbtiles'))
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

final catalogRepositoryProvider =
    Provider<CatalogRepository>((ref) => CatalogRepository(catalogUrl: Uri.parse(AppConfig.mapsCatalogUrl)));

/// The current catalog; [refresh] pulls a newer one from a URL.
class CatalogNotifier extends AsyncNotifier<List<MapProvider>> {
  @override
  Future<List<MapProvider>> build() async {
    final repository = ref.read(catalogRepositoryProvider);
    final providers = await repository.load();
    final url = repository.catalogUrl;
    if (url != null) unawaited(_refreshQuietly(url));
    return providers;
  }

  /// The server's catalog at start-up. Without a connection the built-in
  /// catalog simply stays.
  Future<void> _refreshQuietly(Uri url) async {
    try {
      await refresh(url);
    } catch (_) {}
  }

  Future<void> refresh(Uri url) async {
    final repository = ref.read(catalogRepositoryProvider);
    await repository.refreshFromUrl(url);
    state = AsyncData(await repository.load());
  }

  /// Re-reads local files, e.g. after a .mbtiles import.
  Future<void> reload() async => state = AsyncData(await ref.read(catalogRepositoryProvider).load());
}

final catalogProvider = AsyncNotifierProvider<CatalogNotifier, List<MapProvider>>(CatalogNotifier.new);
