import 'dart:io';

import 'package:app/exceptions/storage_exception.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Где sabyrmap хранит файлы на устройстве. Все пути строятся от одного
/// корня [appRoot], который определяется один раз при старте.
///
/// Пути в стиле POSIX (`/`), как на Android.
class StoragePaths {
  StoragePaths._(this._appRoot);

  /// Пути от заданного корня — для тестов и явной настройки.
  factory StoragePaths.forRoot(String appRoot) => StoragePaths._(_posix.normalize(appRoot));

  static final p.Context _posix = p.posix;
  static Future<StoragePaths>? _cached;

  final String _appRoot;

  /// Определяет корень приложения (один раз; дальше — из кэша) — папку
  /// [mediafileFolderName] внутри первой доступной из:
  /// 1. внешняя папка приложения (`/Android/data/<pkg>/files`);
  /// 2. папка документов приложения;
  /// 3. папка служебных данных приложения;
  /// 4. если ничего не доступно — [StorageException].
  static Future<StoragePaths> resolve() {
    final future = _cached ??= resolveWith([
      getExternalStorageDirectory,
      getApplicationDocumentsDirectory,
      getApplicationSupportDirectory,
    ]);
    // Неудачу не кэшируем: следующий вызов попробует снова.
    return future.catchError((Object e) {
      _cached = null;
      throw e;
    });
  }

  /// Первый доступный корень из [candidates] (по порядку), без кэша.
  @visibleForTesting
  static Future<StoragePaths> resolveWith(List<Future<Directory?> Function()> candidates) async {
    final failures = <Object>[];
    for (final candidate in candidates) {
      try {
        final dir = await candidate();
        if (dir != null) return StoragePaths.forRoot(_posix.join(dir.path, mediafileFolderName));
      } catch (e) {
        failures.add(e);
      }
    }
    throw StorageException(
      'No app storage directory is available',
      cause: failures.isEmpty ? null : failures.join('; '),
    );
  }

  /// Сбросить кэш [resolve].
  @visibleForTesting
  static void resetCache() => _cached = null;

  /// Папка, в которой лежит всё приложение: карты, метки, значки и прочее.
  static const String mediafileFolderName = 'mediafile';

  String get appRoot => _appRoot;
  String get landmarks => _posix.join(_appRoot, 'landmarks');
  String get datastore => _posix.join(_appRoot, 'datastore');
  String get datastoreMaps => _posix.join(datastore, 'maps');
  String get datastoreDem => _posix.join(datastore, 'dem');
  String get icons => _posix.join(_appRoot, 'icons');
  String get logs => _posix.join(_appRoot, 'logs');
  String get maps => _posix.join(_appRoot, 'maps');
  String get pictures => _posix.join(_appRoot, 'pictures');

  /// «Несортированные метки» — общая папка меток по умолчанию: сюда же
  /// импортируются внешние файлы.
  String get importDefault => _posix.join(landmarks, unsortedFolderName);

  /// «Записанные треки» — куда рекордер пишет треки.
  String get recordedTracks => _posix.join(landmarks, recordedTracksFolderName);

  static const String unsortedFolderName = 'Несортированные метки';
  static const String recordedTracksFolderName = 'Записанные треки';

  /// Прежние (латинские) имена папок меток → новые.
  Map<String, String> get legacyFolders => {
    _posix.join(landmarks, 'imported'): importDefault,
    _posix.join(landmarks, 'recorded_tracks'): recordedTracks,
  };

  /// Папки, которые раньше лежали рядом с [mediafileFolderName] (прямо в
  /// `files/`), → их место внутри неё. Пусто, если корень — не
  /// [mediafileFolderName].
  Map<String, String> get legacyRootFolders {
    if (_posix.basename(_appRoot) != mediafileFolderName) return const {};
    final parent = _posix.dirname(_appRoot);
    return {
      for (final name in const ['landmarks', 'datastore', 'icons', 'logs', 'maps', 'pictures'])
        _posix.join(parent, name): _posix.join(_appRoot, name),
    };
  }

  /// Все базовые папки, которые создаёт [StorageService.ensureBaseFolders].
  List<String> get baseFolders => [
    landmarks,
    datastore,
    datastoreMaps,
    datastoreDem,
    icons,
    logs,
    maps,
    pictures,
    importDefault,
    recordedTracks,
  ];

  /// Абсолютный путь файла [filename] внутри [landmarks].
  ///
  /// Decision: допускаются подпапки (`Поход/a.wpt`), но путь, который
  /// выходит за пределы [landmarks] (абсолютный или через `..`),
  /// сводится к одному имени файла в [landmarks]. Исключений не бросает.
  String resolveInLandmarks(String filename) {
    final candidate = _posix.normalize(_posix.join(landmarks, filename));
    if (_posix.isWithin(landmarks, candidate)) return candidate;
    final name = _posix.basename(filename);
    return name.isEmpty || name == '.' || name == '..' ? landmarks : _posix.join(landmarks, name);
  }
}
