import 'dart:io';

import 'package:app/exceptions/folder_exception.dart';
import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Папки, куда сохраняются метки: по умолчанию и текущая.
class FolderService {
  FolderService(this._paths, this._settings);

  final StoragePaths _paths;
  final AppSettings _settings;

  /// Кому сообщать о переименованных и удалённых папках и файлах
  /// ([LandmarkIndex.refresh]).
  Future<void> Function(Iterable<String> paths)? onChanged;

  /// Папка по умолчанию из настроек или «Несортированные метки». Если
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

  /// Можно ли менять папку (переименовать, удалить, вырезать): только
  /// внутри «Мои метки», кроме служебных «Несортированные метки» и
  /// «Записанные треки». Корень, его родители и разделы вроде загрузок —
  /// нельзя.
  bool isEditable(String path) {
    final normalized = p.normalize(path);
    if (!p.isWithin(_paths.landmarks, normalized)) return false;
    return !p.equals(normalized, _paths.importDefault) && !p.equals(normalized, _paths.recordedTracks);
  }

  /// Создаёт подпапку [name] в [parent]. Неверное имя или такая папка уже
  /// есть — [FolderException].
  Future<String> createSubfolder(String parent, String name) async {
    final clean = _checkName(name);
    final path = p.join(parent, clean);
    if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.notFound) {
      throw FolderException('уже существует', path: path);
    }
    await ensureFolder(path);
    return path;
  }

  /// Переименовывает или переносит папку внутри «Мои метки». Защищённая
  /// папка, цель снаружи «Мои метки», цель внутри самой папки или уже
  /// существующая цель — [FolderException].
  Future<void> rename(String oldPath, String newPath) async {
    if (!isEditable(oldPath)) throw FolderException('Действие недоступно', path: oldPath);
    if (!p.isWithin(_paths.landmarks, newPath)) throw FolderException('Нельзя вынести за пределы меток', path: newPath);
    if (p.equals(oldPath, newPath) || isDescendant(oldPath, newPath)) {
      throw FolderException('Нельзя переместить папку в саму себя', path: newPath);
    }
    if (await FileSystemEntity.type(newPath, followLinks: false) != FileSystemEntityType.notFound) {
      throw FolderException('уже существует', path: newPath);
    }
    try {
      await Directory(oldPath).rename(newPath);
    } on FileSystemException catch (e) {
      throw StorageException('Cannot rename folder', path: oldPath, cause: e);
    }
    await onChanged?.call([oldPath, newPath]);
  }

  /// Удаляет папку со всем содержимым, без возврата. Защищённая папка —
  /// [FolderException].
  Future<void> deleteRecursive(String path) async {
    if (!isEditable(path)) throw FolderException('Действие недоступно', path: path);
    try {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      throw StorageException('Cannot delete folder', path: path, cause: e);
    }
    await onChanged?.call([path]);
  }

  /// Подпапки, файлы, размер и время последнего изменения папки (с
  /// вложенными; симлинки не учитываются).
  Future<FolderDetails> details(String path) async {
    var folders = 0;
    var files = 0;
    var bytes = 0;
    final dir = Directory(path);
    var last = (await dir.stat()).modified.millisecondsSinceEpoch;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        final stat = await e.stat();
        if (stat.modified.millisecondsSinceEpoch > last) last = stat.modified.millisecondsSinceEpoch;
        if (e is Directory) {
          folders++;
        } else if (e is File) {
          files++;
          bytes += stat.size;
        }
      }
    } on FileSystemException catch (e) {
      throw StorageException('Cannot read folder', path: path, cause: e);
    }
    return FolderDetails(path: path, folderCount: folders, fileCount: files, totalBytes: bytes, lastModifiedMs: last);
  }

  /// Переименовывает файл в его же папке и возвращает новый путь.
  /// [newName] — имя без расширения (оно сохраняется); занятое имя
  /// получает `_1`, `_2`, ... Недопустимое имя — [FolderException].
  Future<String> renameFile(String oldPath, String newName) async {
    final ext = p.extension(oldPath);
    var name = _checkName(newName);
    if (ext.isNotEmpty && p.extension(name).toLowerCase() == ext.toLowerCase()) {
      name = p.basenameWithoutExtension(name);
    }
    if (name == p.basenameWithoutExtension(oldPath)) return oldPath;
    if (!await File(oldPath).exists()) throw StorageException('File to rename does not exist', path: oldPath);
    final target = await FileNaming.resolveCollision(p.dirname(oldPath), '$name$ext');
    try {
      await File(oldPath).rename(target);
    } on FileSystemException catch (e) {
      throw StorageException('Cannot rename file', path: oldPath, cause: e);
    }
    await onChanged?.call([oldPath, target]);
    return target;
  }

  /// Удаляет файл без возврата; отсутствующий файл — не ошибка.
  Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      throw StorageException('Cannot delete file', path: path, cause: e);
    }
  }

  /// Размер файла в байтах.
  Future<int> fileSize(String path) async => (await _statFile(path)).size;

  /// Время последнего изменения файла, Unix ms.
  Future<int> fileModifiedMs(String path) async => (await _statFile(path)).modified.millisecondsSinceEpoch;

  static Future<FileStat> _statFile(String path) async {
    final stat = await FileStat.stat(path);
    if (stat.type != FileSystemEntityType.file) throw StorageException('File does not exist', path: path);
    return stat;
  }

  /// Имя папки без `/` и `\`, не пустое и не «.»/«..».
  static String _checkName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..' || trimmed.contains(RegExp(r'[/\\]'))) {
      throw FolderException('Недопустимое имя «$name»');
    }
    return trimmed;
  }

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

/// Сводка по папке.
class FolderDetails {
  const FolderDetails({
    required this.path,
    required this.folderCount,
    required this.fileCount,
    required this.totalBytes,
    required this.lastModifiedMs,
  });

  final String path;

  /// Вложенных папок на всех уровнях.
  final int folderCount;

  /// Файлов на всех уровнях.
  final int fileCount;
  final int totalBytes;

  /// Unix ms самого свежего изменения внутри.
  final int lastModifiedMs;
}
