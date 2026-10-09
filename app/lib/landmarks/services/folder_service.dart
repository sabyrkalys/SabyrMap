import 'dart:io';

import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Папки, куда сохраняются метки: по умолчанию и текущая.
class FolderService {
  FolderService(this._paths, this._settings);

  final StoragePaths _paths;
  final AppSettings _settings;

  /// Папка по умолчанию из настроек или `<landmarks>/imported`. Если
  /// сохранённой папки больше нет, настройка сбрасывается.
  Future<String> getDefaultFolder() async =>
      await _existingOrReset(SettingsKeys.defaultFolder) ?? _paths.importDefault;

  /// Запоминает папку по умолчанию. Саму папку не создаёт — см. [ensureFolder].
  Future<void> setDefaultFolder(String path) => _settings.setString(SettingsKeys.defaultFolder, _normalize(path));

  /// Папка, открытая сейчас в проводнике меток; null — не выбрана.
  /// Decision: как и папка по умолчанию, удалённая папка сбрасывается в null.
  Future<String?> getCurrentFolder() => _existingOrReset(SettingsKeys.currentFolder);

  /// Запоминает текущую папку; null — забыть.
  Future<void> setCurrentFolder(String? path) => path == null
      ? _settings.remove(SettingsKeys.currentFolder)
      : _settings.setString(SettingsKeys.currentFolder, _normalize(path));

  /// Подпапки [parent] (без симлинков), абсолютные пути по алфавиту.
  /// Нет папки — пустой список.
  Future<List<String>> listSubfolders(String parent) async {
    final dir = Directory(parent);
    if (!await dir.exists()) return const [];
    try {
      final folders = [
        await for (final entity in dir.list(followLinks: false))
          if (entity is Directory) entity.path,
      ];
      return folders..sort();
    } on FileSystemException catch (e) {
      throw StorageException('Cannot list folder', path: parent, cause: e);
    }
  }

  /// Подпапки и файлы [directory] раздельно (без симлинков), абсолютные
  /// пути по алфавиту. Нет папки — оба списка пусты.
  Future<({List<String> folders, List<String> files})> listContents(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) return (folders: <String>[], files: <String>[]);
    final folders = <String>[];
    final files = <String>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          folders.add(entity.path);
        } else if (entity is File) {
          files.add(entity.path);
        }
      }
    } on FileSystemException catch (e) {
      throw StorageException('Cannot list folder', path: directory, cause: e);
    }
    return (folders: folders..sort(), files: files..sort());
  }

  /// Есть ли папка [path] (симлинк на папку тоже считается).
  Future<bool> folderExists(String path) => Directory(path).exists();

  /// Лежит ли [child] где-то внутри [parent] (сама папка — нет).
  /// Только по путям, без обращения к диску.
  bool isDescendant(String parent, String child) => p.isWithin(p.normalize(parent), p.normalize(child));

  /// Создаёт папку со всеми родителями, если её нет.
  Future<void> ensureFolder(String path) async {
    try {
      await Directory(path).create(recursive: true);
    } on FileSystemException catch (e) {
      throw StorageException('Cannot create folder', path: path, cause: e);
    }
  }

  Future<String?> _existingOrReset(String key) async {
    final saved = _settings.getString(key);
    if (saved == null) return null;
    if (await Directory(saved).exists()) return saved;
    await _settings.remove(key);
    return null;
  }

  static String _normalize(String path) {
    if (path.trim().isEmpty) throw ArgumentError.value(path, 'path', 'must not be empty');
    return p.normalize(path);
  }
}
