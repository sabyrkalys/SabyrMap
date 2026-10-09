import 'dart:convert';
import 'dart:io';

import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'backup_data_type.dart';
import 'backup_manifest.dart';
import 'restore_request.dart';
import 'restore_result.dart';

/// Восстановление из резервной копии [BackupService].
///
/// - Манифест новее поддерживаемого или испорчен — неудача.
/// - [RestoreRequest.overwriteExisting]: папки выбранных типов сначала
///   очищаются; иначе существующие файлы не трогаются (предупреждение).
///   Decision: метки при совпадении имени не пропускаются, а
///   восстанавливаются рядом с суффиксом `_restored` — не смешиваясь с
///   существующими и не теряясь.
/// - Настройки записываются поверх текущих, нужен перезапуск.
/// - Отката нет: уже восстановленное остаётся.
class RestoreService {
  RestoreService(this._paths, this._storage, this._settings);

  final StoragePaths _paths;
  final StorageService _storage;
  final AppSettings _settings;

  Future<RestoreResult> restore(RestoreRequest request) async {
    if (!await File(request.sourcePath).exists()) {
      return RestoreResult.failure('Backup file not found: ${request.sourcePath}');
    }
    InputFileStream? input;
    try {
      input = InputFileStream(request.sourcePath);
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input);
      } on Object catch (e) {
        return RestoreResult.failure('Not a backup archive: $e');
      }
      final manifestFile = archive.findFile(BackupManifest.fileName);
      if (manifestFile == null) return RestoreResult.failure('The archive has no manifest');
      final BackupManifest manifest;
      try {
        manifest = BackupManifest.decode(utf8.decode(manifestFile.content));
      } on FormatException catch (e) {
        return RestoreResult.failure(e.message);
      }
      if (manifest.version > BackupManifest.currentVersion) {
        return RestoreResult.failure('Backup version ${manifest.version} is newer than supported');
      }
      return await _restore(archive, manifest, request);
    } finally {
      await input?.close();
    }
  }

  Future<RestoreResult> _restore(Archive archive, BackupManifest manifest, RestoreRequest request) async {
    final warnings = <String>[];
    final inBackup = {for (final e in manifest.entries) e.type};
    var restored = 0;
    var settingsRestored = false;
    for (final type in BackupDataType.values.where(request.effectiveTypes.contains)) {
      if (!inBackup.contains(type)) {
        warnings.add('${type.name} is not in this backup');
        continue;
      }
      try {
        if (type.folder != null) {
          restored += await _restoreFolder(archive, type, request.overwriteExisting, warnings);
        } else {
          final file = archive.findFile(type.settingsFile!);
          if (file == null) {
            warnings.add('${type.settingsFile} is missing from the archive');
            continue;
          }
          final values = jsonDecode(utf8.decode(file.content)) as Map<String, dynamic>;
          await _settings.importAll(values);
          restored++;
          settingsRestored = true;
        }
      } on Exception catch (e) {
        return RestoreResult.failure('Restoring ${type.name} failed: $e', warnings: warnings, restoredFiles: restored);
      } on TypeError catch (e) {
        return RestoreResult.failure('Restoring ${type.name} failed: $e', warnings: warnings, restoredFiles: restored);
      }
    }
    return RestoreResult(success: true, restoredFiles: restored, warnings: warnings, needsRestart: settingsRestored);
  }

  Future<int> _restoreFolder(Archive archive, BackupDataType type, bool overwrite, List<String> warnings) async {
    final prefix = '${type.folder}/';
    final target = _folderOf(type);
    if (overwrite) await _storage.deleteDirectory(target);
    await Directory(target).create(recursive: true);
    var count = 0;
    for (final file in archive.files) {
      if (!file.isFile || !file.name.startsWith(prefix)) continue;
      final relative = file.name.substring(prefix.length);
      final parts = p.posix.split(relative);
      if (relative.isEmpty || parts.contains('..') || p.posix.isAbsolute(relative)) {
        warnings.add('Unsafe path ${file.name} skipped');
        continue;
      }
      var path = p.joinAll([target, ...parts]);
      if (await File(path).exists()) {
        if (type == BackupDataType.landmarks) {
          path = await _restoredName(path);
          warnings.add('${file.name} exists; restored as ${p.basename(path)}');
        } else {
          warnings.add('${file.name} exists; kept the current file');
          continue;
        }
      }
      await Directory(p.dirname(path)).create(recursive: true);
      final out = OutputFileStream(path);
      try {
        file.writeContent(out);
      } finally {
        await out.close();
      }
      count++;
    }
    return count;
  }

  /// `name_restored.ext`, `name_restored_1.ext`, ...
  static Future<String> _restoredName(String path) async {
    final dir = p.dirname(path);
    final ext = p.extension(path);
    final stem = '${p.basenameWithoutExtension(path)}_restored';
    var candidate = p.join(dir, '$stem$ext');
    for (var i = 1; await File(candidate).exists(); i++) {
      candidate = p.join(dir, '${stem}_$i$ext');
    }
    return candidate;
  }

  String _folderOf(BackupDataType type) => switch (type) {
    BackupDataType.landmarks => _paths.landmarks,
    BackupDataType.icons => _paths.icons,
    BackupDataType.maps => _paths.maps,
    BackupDataType.onDemand => _paths.datastoreMaps,
    BackupDataType.dem => _paths.datastoreDem,
    _ => throw ArgumentError.value(type, 'type', 'not a folder type'),
  };
}
