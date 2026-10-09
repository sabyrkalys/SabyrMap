import 'dart:convert';
import 'dart:io';

import 'package:app/app_settings/app_settings_keys.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'backup_data_type.dart';
import 'backup_manifest.dart';
import 'backup_manifest_entry.dart';
import 'backup_request.dart';
import 'backup_result.dart';
import 'size_estimator.dart';

/// Резервная копия в ZIP: `manifest.json`, папки данных, JSON настроек.
/// Исходные файлы не меняются; архив пишется во временный файл рядом и
/// переименовывается в конце.
///
/// Decision: [LandmarkServices] в конструктор не передаётся (сервис сам
/// в нём живёт); всё нужное — пути, файлы, настройки.
class BackupService {
  BackupService(
    this._paths,
    this._storage,
    this._settings, {
    this.appVersion = '1.0.0',
    this.maxArchiveBytes = defaultMaxArchiveBytes,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 4 ГБ — предел ZIP без расширений.
  static const int defaultMaxArchiveBytes = 4 * 1024 * 1024 * 1024;

  final StoragePaths _paths;
  final StorageService _storage;
  final AppSettings _settings;
  final String appVersion;
  final int maxArchiveBytes;
  final DateTime Function() _clock;

  Future<BackupResult> backup(BackupRequest request) async {
    final types = request.effectiveTypes;
    if (types.isEmpty) return BackupResult.failure('Nothing selected to back up');
    final dir = p.dirname(request.targetPath);
    final access = await _storage.checkWriteAccess(dir);
    if (!access.granted) return BackupResult.failure('Cannot write to $dir: ${access.reason}');

    final size = await estimateSize(request);
    if (size > maxArchiveBytes) {
      return BackupResult.failure(
        'Backup is too large',
        warnings: ['${(size / (1 << 20)).toStringAsFixed(0)} MB exceeds the ${maxArchiveBytes >> 20} MB archive limit'],
      );
    }

    final temp = '${request.targetPath}.tmp';
    final encoder = ZipFileEncoder();
    final entries = <BackupManifestEntry>[];
    var totalBytes = 0;
    var totalFiles = 0;
    try {
      encoder.create(temp);
      for (final type in BackupDataType.values.where(types.contains)) {
        final (bytes, files) = type.folder != null
            ? await _addFolderType(encoder, type, request)
            : _addSettingsType(encoder, type);
        entries.add(BackupManifestEntry(type: type, relativePath: type.archivePath, byteCount: bytes, fileCount: files));
        totalBytes += bytes;
        totalFiles += files;
      }
      final manifest = BackupManifest(
        createdAt: _clock().millisecondsSinceEpoch,
        appVersion: appVersion,
        entries: entries,
      );
      encoder.addArchiveFile(
        ArchiveFile.bytes(BackupManifest.fileName, utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest.toJson()))),
      );
      await encoder.close();
      await File(temp).rename(request.targetPath);
    } on Exception catch (e) {
      try {
        await encoder.close();
      } on Object {
        // Архив уже закрыт.
      }
      final tmp = File(temp);
      if (await tmp.exists()) await tmp.delete();
      return BackupResult.failure('Backup failed: $e');
    }
    return BackupResult(success: true, filePath: request.targetPath, totalBytes: totalBytes, totalFiles: totalFiles);
  }

  /// Размер данных до сжатия.
  Future<int> estimateSize(BackupRequest request) async {
    var total = 0;
    for (final type in request.effectiveTypes) {
      if (type == BackupDataType.landmarks) {
        for (final folder in _landmarkFolders(request)) {
          total += await SizeEstimator.estimateFolder(folder);
        }
      } else if (type.folder != null) {
        total += await SizeEstimator.estimateFolder(_folderOf(type));
      } else {
        total += utf8.encode(SizeEstimator.encodeSettings(_settingsFor(type))).length;
      }
    }
    return total;
  }

  /// Папка данных типа на устройстве.
  String _folderOf(BackupDataType type) => switch (type) {
    BackupDataType.landmarks => _paths.landmarks,
    BackupDataType.icons => _paths.icons,
    BackupDataType.maps => _paths.maps,
    BackupDataType.onDemand => _paths.datastoreMaps,
    BackupDataType.dem => _paths.datastoreDem,
    _ => throw ArgumentError.value(type, 'type', 'not a folder type'),
  };

  /// Папки меток для копии: все или выбранные (только внутри landmarks).
  List<String> _landmarkFolders(BackupRequest request) => request.includeFullLandmarks
      ? [_paths.landmarks]
      : [
          for (final f in request.includedFolders)
            if (p.isWithin(_paths.landmarks, f) || p.equals(_paths.landmarks, f)) p.normalize(f),
        ];

  Future<(int, int)> _addFolderType(ZipFileEncoder encoder, BackupDataType type, BackupRequest request) async {
    final base = _folderOf(type);
    final folders = type == BackupDataType.landmarks ? _landmarkFolders(request) : [base];
    var bytes = 0;
    var files = 0;
    final added = <String>{};
    for (final folder in folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File || !added.add(e.path)) continue;
        final name = p.posix.joinAll([type.folder!, ...p.split(p.relative(e.path, from: base))]);
        await encoder.addFile(e, name);
        bytes += await e.length();
        files++;
      }
    }
    return (bytes, files);
  }

  (int, int) _addSettingsType(ZipFileEncoder encoder, BackupDataType type) {
    final data = utf8.encode(SizeEstimator.encodeSettings(_settingsFor(type)));
    encoder.addArchiveFile(ArchiveFile.bytes(type.settingsFile!, data));
    return (data.length, 1);
  }

  Map<String, Object> _settingsFor(BackupDataType type) {
    final all = _settings.exportAll();
    bool Function(String) keep = switch (type) {
      BackupDataType.workspaces => AppSettingsKeys.isWorkspaceKey,
      BackupDataType.favoriteSets => AppSettingsKeys.isFavoriteSetsKey,
      BackupDataType.proximityAlerts => AppSettingsKeys.isProximityKey,
      _ => (_) => true,
    };
    return {for (final e in all.entries) if (keep(e.key)) e.key: e.value};
  }
}
