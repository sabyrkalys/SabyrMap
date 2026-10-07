import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file/file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng, LatLngBounds;

import '../../config.dart';
import '../../mediafile/mediafile_folder_service.dart';
import '../../mediafile/mediafile_subfolders.dart';
import '../models/map_models.dart';
import 'file_downloader.dart';
import 'regions_api.dart';

/// Whether the phone is on Wi-Fi (or Ethernet) right now.
abstract class NetworkInfo {
  Future<bool> isOnWifi();
}

class ConnectivityNetworkInfo implements NetworkInfo {
  const ConnectivityNetworkInfo();

  @override
  Future<bool> isOnWifi() async {
    final kinds = await Connectivity().checkConnectivity();
    return kinds.contains(ConnectivityResult.wifi) || kinds.contains(ConnectivityResult.ethernet);
  }
}

/// Free space on the volume that holds a path.
abstract class StorageInfo {
  /// Null when unknown.
  Future<int?> freeBytes(String path);

  /// Size of the volume holding [path]; null when unknown.
  Future<int?> totalBytes(String path);
}

/// Android StatFs through MainActivity's `sabyrmap/storage` channel.
class PlatformStorageInfo implements StorageInfo {
  const PlatformStorageInfo();

  static const _channel = MethodChannel('sabyrmap/storage');

  @override
  Future<int?> freeBytes(String path) => _stat('freeBytes', path);

  @override
  Future<int?> totalBytes(String path) => _stat('totalBytes', path);

  Future<int?> _stat(String method, String path) async {
    try {
      return await _channel.invokeMethod<int>(method, {'path': path});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

enum RegionStage {
  /// The server is cutting the region.
  preparing,
  downloading,
  installing,
}

class RegionProgress {
  const RegionProgress(this.stage, this.fraction);

  final RegionStage stage;

  /// 0–1 within the stage.
  final double fraction;
}

/// What the save dialog shows before the user confirms.
class RegionCheck {
  const RegionCheck({required this.estimate, required this.freeBytes});

  final RegionEstimate estimate;
  final int? freeBytes;

  bool get fitsOnPhone => freeBytes == null || estimate.totalBytes < freeBytes!;

  bool get canSave => estimate.allowed && fitsOnPhone;
}

/// Offline regions cut by our map server (POST /regions), installed into
/// `mediafile/maps/<name>/` as MBTiles + an offline style.
///
/// The style the server sends has `{{REGION_DIR}}` where the folder goes; it
/// is replaced with the real path here. The world overview package («Обзор
/// мира») comes along with the first region; later regions borrow its
/// overview tiles so the whole world has a background offline.
class ServerRegionService {
  ServerRegionService({
    required RegionsApi api,
    required MediaFileFolderService mapsFolder,
    NetworkInfo network = const ConnectivityNetworkInfo(),
    StorageInfo storage = const PlatformStorageInfo(),
    this.pollInterval = const Duration(seconds: 2),
  })  : _api = api,
        _mapsFolder = mapsFolder,
        _network = network,
        _storage = storage;

  static const String overviewFolderName = 'Обзор мира';
  static const int overviewMaxZoom = 5;
  static const int defaultMaxZoom = 16;

  /// The server's REGION_MAX_ZOOM.
  static const int maxRegionZoom = 17;

  static const String regionDirPlaceholder = '{{REGION_DIR}}';
  // LatLng wraps longitude 180 to -180, which would make the world zero wide.
  static final LatLngBounds world = LatLngBounds(
    southwest: const LatLng(-85, -180),
    northeast: const LatLng(85, 179.99999),
  );

  final RegionsApi _api;
  final MediaFileFolderService _mapsFolder;
  final NetworkInfo _network;
  final StorageInfo _storage;
  final Duration pollInterval;

  static bool canDownload(MapSource source) => source.downloadable;

  /// Highest zoom worth asking for: the map's own, within the server limit.
  static int zoomLimit(MapSource source) => source.maxZoom.clamp(0, maxRegionZoom);

  Future<RegionCheck> check({required MapSource source, required LatLngBounds bounds, required int maxZoom}) async {
    final estimate = await _api.estimate(mapId: source.id, bounds: bounds, maxZoom: maxZoom);
    final dir = await _mapsFolder.directory();
    return RegionCheck(estimate: estimate, freeBytes: await _storage.freeBytes(dir.path));
  }

  Future<bool> hasOverview() async {
    final dir = (await _mapsFolder.directory()).childDirectory(overviewFolderName);
    return dir.childFile('overview.mbtiles').existsSync();
  }

  /// Downloads the world overview package unless it is already there.
  Future<void> ensureOverview({
    required MapSource source,
    bool wifiOnly = true,
    void Function(RegionProgress)? onProgress,
    CancelToken? cancel,
  }) async {
    if (await hasOverview()) return;
    await install(
      source: source,
      bounds: world,
      maxZoom: overviewMaxZoom,
      name: overviewFolderName,
      wifiOnly: wifiOnly,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  /// Orders the region, waits for the server, downloads and installs it.
  /// Returns the region folder. Safe to call again after a failure: finished
  /// files are kept and a half-downloaded one continues where it stopped.
  Future<Directory> install({
    required MapSource source,
    required LatLngBounds bounds,
    required int maxZoom,
    required String name,
    bool wifiOnly = true,
    void Function(RegionProgress)? onProgress,
    CancelToken? cancel,
  }) async {
    if (!canDownload(source)) throw RegionException('Карту «${source.name}» нельзя скачать с сервера');
    if (wifiOnly && !await _network.isOnWifi()) {
      throw const RegionException('Нет Wi-Fi. Подключитесь к Wi-Fi или разрешите скачивание по мобильной сети');
    }
    void check() {
      if (cancel?.isCancelled ?? false) throw const DownloadCancelled();
    }

    var job = await _api.create(mapId: source.id, bbox: bboxOf(bounds), maxZoom: maxZoom, name: name);
    while (job.status == RegionJobStatus.queued || job.status == RegionJobStatus.running) {
      onProgress?.call(RegionProgress(RegionStage.preparing, job.progress));
      await Future<void>.delayed(pollInterval);
      check();
      job = await _api.get(job.id);
    }
    if (job.status != RegionJobStatus.ready) {
      throw RegionException(job.status == RegionJobStatus.failed
          ? 'Сервер не смог подготовить участок: ${job.error ?? 'неизвестная ошибка'}'
          : 'Участок на сервере устарел — закажите его снова');
    }

    final folder = (await _mapsFolder.directory()).childDirectory(folderNameFor(name));
    folder.createSync(recursive: true);
    final total = job.files.fold<int>(0, (sum, f) => sum + f.size);
    var done = 0;
    for (final file in job.files) {
      if (file.name == 'style.zip' && folder.childFile('style.json').existsSync()) {
        done += file.size; // installed by an earlier, interrupted run
        continue;
      }
      await downloadFile(
        client: _api.httpClient,
        url: _api.downloadUri(job.id, file.name),
        target: folder.childFile(file.name),
        expectedSize: file.size,
        sha256Hex: file.sha256,
        cancel: cancel,
        onProgress: (bytes) => onProgress?.call(RegionProgress(RegionStage.downloading, (done + bytes) / total)),
      );
      done += file.size;
    }

    onProgress?.call(const RegionProgress(RegionStage.installing, 0));
    final zip = folder.childFile('style.zip');
    if (zip.existsSync()) {
      _extract(zip, folder);
      zip.deleteSync();
      await _writeOfflineStyle(folder);
    }
    onProgress?.call(const RegionProgress(RegionStage.installing, 1));
    return folder;
  }

  /// A folder name that is safe on Android storage.
  static String folderNameFor(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned;
    return short.isEmpty || short.startsWith('.') ? 'Участок' : short;
  }

  void _extract(File zip, Directory folder) {
    final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    final root = folder.absolute.path;
    for (final entry in archive) {
      final target = folder.fileSystem.file(folder.fileSystem.path.normalize(folder.fileSystem.path.join(root, entry.name)));
      // Never write outside the region folder, whatever the archive says.
      if (!target.path.startsWith('$root${folder.fileSystem.path.separator}')) continue;
      if (entry.isFile) {
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(entry.content as List<int>);
      }
    }
  }

  Future<void> _writeOfflineStyle(Directory folder) async {
    final file = folder.childFile('style.json');
    var text = file.readAsStringSync().replaceAll(regionDirPlaceholder, folder.absolute.path);
    final style = jsonDecode(text) as Map<String, dynamic>;
    final overview = (await _mapsFolder.directory()).childDirectory(overviewFolderName).childFile('overview.mbtiles');
    final sources = style['sources'] as Map<String, dynamic>? ?? {};
    final own = sources['overview'] as Map<String, dynamic>?;
    // The region only has overview tiles over its own area; the package has
    // the whole world.
    if (own != null && overview.existsSync() && folder.basename != overviewFolderName) {
      own['url'] = 'mbtiles://${overview.absolute.path}';
      final ownFile = folder.childFile('overview.mbtiles');
      if (ownFile.existsSync()) ownFile.deleteSync();
    }
    text = const JsonEncoder.withIndent(' ').convert(style);
    file.writeAsStringSync(text);
  }
}

final serverRegionServiceProvider = Provider<ServerRegionService>((ref) => ServerRegionService(
      api: RegionsApi(baseUrl: AppConfig.apiBaseUrl),
      mapsFolder: MediaFileFolderService(subfolder: kMapsSubfolder),
    ));
