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
  static const String serverSatelliteSourceId = 'server-sat-ukraine';
  static const String serverHybridSourceId = 'server-hybrid-ukraine';

  /// Base map shown when the user has not chosen one yet.
  static const String defaultBaseSourceId = serverSatelliteSourceId;

  final MediaFileFolderService _mapsFolder;
  final http.Client _http;
  final AssetBundle _bundle;
  final UserSourcesStore _userSources;
  final FileSystem _fileSystem;
  final String _mapServerBaseUrl;

  /// Providers left out of [load] (see AppConfig.hiddenMapProviders).
  final Set<String> hiddenProviderIds;

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

  /// Our own tile server («Сервер карт»). Used as a fallback when no remote
  /// catalog is loaded: once [refreshFromUrl] succeeds the server supplies
  /// its own maps in that catalog, so this built-in copy is dropped.
  MapProvider _serverProvider() {
    const satAttribution = 'Esri, Maxar, Earthstar Geographics, and the GIS Community';
    const hybridAttribution = '$satAttribution · © OpenStreetMap contributors';
    return MapProvider(
      id: serverProviderId,
      name: 'Сервер карт',
      attribution: satAttribution,
      sources: [
        MapSource(
          id: serverHybridSourceId,
          name: 'Украина · спутник + дороги',
          // Vector style: satellite raster + OSM vector (roads, buildings,
          // labels) drawn on top. MapLibre accepts the style JSON inline.
          styleUrl: _hybridStyle(hybridAttribution),
          format: TileFormat.vector,
          storageMode: StorageMode.onlineOnly,
          attribution: hybridAttribution,
          minZoom: 0,
          maxZoom: 22,
        ),
        MapSource(
          id: serverSatelliteSourceId,
          name: 'Украина · спутник',
          tileUrlTemplate: '$_mapServerBaseUrl/satellite/{z}/{x}/{y}',
          format: TileFormat.raster,
          storageMode: StorageMode.onlineOnly,
          attribution: satAttribution,
          minZoom: 0,
          maxZoom: 16,
        ),
      ],
    );
  }

  /// MapLibre style (as a JSON string) for the hybrid base: our satellite
  /// raster with the OSM vector layer (roads, buildings, place labels) on top.
  /// Vector tiles come from Martin's `osm` source; glyphs from OpenFreeMap for
  /// now (served by our server once fonts are published).
  String _hybridStyle(String attribution) => jsonEncode({
        'version': 8,
        'glyphs': 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
        'sources': {
          'sat': {
            'type': 'raster',
            'tiles': ['$_mapServerBaseUrl/satellite/{z}/{x}/{y}'],
            'tileSize': 256,
            'minzoom': 0,
            'maxzoom': 16,
            'attribution': attribution,
          },
          'osm': {
            'type': 'vector',
            'tiles': ['$_mapServerBaseUrl/osm/{z}/{x}/{y}'],
            'minzoom': 0,
            'maxzoom': 14,
          },
        },
        'layers': [
          {
            'id': 'background',
            'type': 'background',
            'paint': {'background-color': '#e5e3df'},
          },
          {'id': 'sat', 'type': 'raster', 'source': 'sat'},
          {
            'id': 'buildings',
            'type': 'fill',
            'source': 'osm',
            'source-layer': 'building',
            'minzoom': 14,
            'paint': {
              'fill-color': 'rgba(0,0,0,0.25)',
              'fill-outline-color': 'rgba(255,255,255,0.45)',
            },
          },
          {
            'id': 'roads',
            'type': 'line',
            'source': 'osm',
            'source-layer': 'transportation',
            'paint': {
              'line-color': 'rgba(255,255,255,0.75)',
              'line-width': [
                'interpolate', ['linear'], ['zoom'], 6, 0.4, 12, 1.5, 16, 3.0,
              ],
            },
          },
          {
            'id': 'labels',
            'type': 'symbol',
            'source': 'osm',
            'source-layer': 'place',
            'layout': {
              'text-field': ['get', 'name'],
              'text-font': ['Noto Sans Regular'],
              'text-size': 13,
            },
            'paint': {
              'text-color': '#ffffff',
              'text-halo-color': '#000000',
              'text-halo-width': 1.3,
            },
          },
        ],
      });

  /// «Сервер карт» (built-in fallback only), then the built-in (or refreshed)
  /// providers, then «Установленные карты» when mediafile/maps has files.
  Future<List<MapProvider>> load() async {
    final providers = [
      if (_remote == null) _serverProvider(),
      for (final p in _remote ?? await loadBuiltin())
        if (!hiddenProviderIds.contains(p.id)) p,
    ];
    final local = [...await _localSources(), ...await _userSources.load()];
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

  Future<List<MapSource>> _localSources() async {
    final entries = await _mapsFolder.list();
    return [
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
