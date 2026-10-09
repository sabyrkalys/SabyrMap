import 'dart:io';
import 'dart:math';

import 'package:app/exceptions/storage_exception.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'storage_paths.dart';

/// Файловые операции sabyrmap: базовые папки, проверка прав, атомарная
/// запись. Ошибки файловой системы оборачиваются в [StorageException].
class StorageService {
  StorageService(this._paths, {@visibleForTesting Future<void> Function(String tempPath)? beforeCommit})
    : _beforeCommit = beforeCommit;

  final StoragePaths _paths;

  /// Пути хранилища, с которыми работает сервис.
  StoragePaths get paths => _paths;

  /// Вызывается между записью временного файла и переименованием —
  /// тесты бросают здесь исключение, имитируя сбой посреди записи.
  final Future<void> Function(String tempPath)? _beforeCommit;

  static final Random _random = Random.secure();

  /// Метка временных файлов атомарной записи: `<target>.tmp.<random>`.
  static const String tempMarker = '.tmp.';

  /// Имя файла, которым [checkWriteAccess] проверяет запись.
  static const String writeCheckName = '.write_check';

  /// Создаёт все базовые подпапки, если их нет.
  /// Идемпотентно. Возвращает список созданных путей.
  Future<List<String>> ensureBaseFolders() async {
    final created = <String>[];
    for (final path in _paths.baseFolders) {
      final dir = Directory(path);
      try {
        if (await dir.exists()) continue;
        await dir.create(recursive: true);
        created.add(path);
      } on FileSystemException catch (e) {
        throw StorageException('Cannot create folder', path: path, cause: e);
      }
    }
    return created;
  }

  /// Переносит папки со старыми именами ([StoragePaths.legacyFolders]) в
  /// новые: переименованием, а если новая уже есть — по одному элементу
  /// (занятое имя получает `_1`, `_2`…); пустая старая папка удаляется.
  /// Возвращает, сколько папок перенесено.
  Future<int> migrateLegacyFolders() async {
    var migrated = 0;
    for (final MapEntry(key: from, value: to) in _paths.legacyFolders.entries) {
      final old = Directory(from);
      if (!await old.exists()) continue;
      try {
        if (!await Directory(to).exists()) {
          await old.rename(to);
        } else {
          await for (final entity in old.list(followLinks: false)) {
            await entity.rename(await _freeName(to, p.basename(entity.path)));
          }
          await old.delete();
        }
        migrated++;
      } on FileSystemException catch (e) {
        throw StorageException('Cannot move a folder to its new name', path: from, cause: e);
      }
    }
    return migrated;
  }

  static Future<String> _freeName(String dir, String name) async {
    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    var candidate = p.join(dir, name);
    for (var i = 1; await FileSystemEntity.type(candidate, followLinks: false) != FileSystemEntityType.notFound; i++) {
      candidate = p.join(dir, '${stem}_$i$ext');
    }
    return candidate;
  }

  /// Проверяет, можно ли писать в [dir]: создаёт и удаляет `.write_check`.
  Future<WriteAccess> checkWriteAccess(String dir) async {
    if (!await Directory(dir).exists()) {
      return const WriteAccess(granted: false, reason: 'Directory does not exist');
    }
    final probe = File(p.join(dir, writeCheckName));
    try {
      await probe.writeAsBytes(const [0], flush: true);
      await probe.delete();
      return const WriteAccess(granted: true);
    } on FileSystemException catch (e) {
      return WriteAccess(granted: false, reason: e.osError?.message ?? e.message);
    }
  }

  /// Атомарно пишет байты: временный файл в той же папке, затем rename.
  /// При сбое целевой файл не меняется, временный удаляется.
  Future<void> atomicWriteBytes(String absolutePath, Uint8List bytes) async {
    final temp = File('$absolutePath$tempMarker${_randomSuffix()}');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await _beforeCommit?.call(temp.path);
      await temp.rename(absolutePath);
    } catch (e) {
      await _deleteQuietly(temp);
      if (e is StorageException) rethrow;
      throw StorageException('Cannot write file', path: absolutePath, cause: e);
    }
  }

  /// Читает байты файла целиком.
  Future<Uint8List> readBytes(String absolutePath) async {
    try {
      return await File(absolutePath).readAsBytes();
    } on FileSystemException catch (e) {
      throw StorageException('Cannot read file', path: absolutePath, cause: e);
    }
  }

  /// Удаляет файл. Если файла нет — ничего не делает.
  Future<void> deleteFile(String absolutePath) async {
    try {
      await File(absolutePath).delete();
    } on PathNotFoundException {
      return;
    } on FileSystemException catch (e) {
      if (!await File(absolutePath).exists()) return;
      throw StorageException('Cannot delete file', path: absolutePath, cause: e);
    }
  }

  /// Удаляет папку со всем содержимым. Нет папки — ничего не делает.
  Future<void> deleteDirectory(String absolutePath) async {
    final dir = Directory(absolutePath);
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      throw StorageException('Cannot delete folder', path: absolutePath, cause: e);
    }
  }

  /// Перемещает файл. В пределах одного раздела — rename (атомарно);
  /// между разделами — атомарная копия в [to] и удаление источника.
  Future<void> moveFile(String from, String to) async {
    final source = File(from);
    if (!await source.exists()) throw StorageException('Source file does not exist', path: from);
    try {
      await source.rename(to);
    } on FileSystemException {
      // rename не работает между разделами — копируем.
      await atomicWriteBytes(to, await readBytes(from));
      await deleteFile(from);
    }
  }

  /// Файлы в [dir] (не рекурсивно), отсортированные по пути. [extensions] —
  /// без точки, без учёта регистра; null — любые. Временные файлы атомарной
  /// записи и `.write_check` не попадают в список. Нет папки — пустой список.
  Future<List<FileSystemEntity>> listFiles(String dir, {Set<String>? extensions}) async {
    final directory = Directory(dir);
    if (!await directory.exists()) return const [];
    final wanted = extensions?.map((e) => (e.startsWith('.') ? e.substring(1) : e).toLowerCase()).toSet();
    try {
      final files = <FileSystemEntity>[];
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name == writeCheckName || name.contains(tempMarker)) continue;
        if (wanted != null) {
          final ext = p.extension(name);
          if (ext.isEmpty || !wanted.contains(ext.substring(1).toLowerCase())) continue;
        }
        files.add(entity);
      }
      files.sort((a, b) => a.path.compareTo(b.path));
      return files;
    } on FileSystemException catch (e) {
      throw StorageException('Cannot list folder', path: dir, cause: e);
    }
  }

  static String _randomSuffix() =>
      List.generate(8, (_) => _random.nextInt(16).toRadixString(16)).join();

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Не удалось убрать временный файл — его отфильтрует listFiles.
    }
  }
}

/// Результат [StorageService.checkWriteAccess].
class WriteAccess {
  const WriteAccess({required this.granted, this.reason});

  final bool granted;

  /// Почему запись невозможна (если [granted] == false).
  final String? reason;

  @override
  String toString() => granted ? 'WriteAccess(granted)' : 'WriteAccess(denied: $reason)';
}
