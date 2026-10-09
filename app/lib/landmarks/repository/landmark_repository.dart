import 'dart:io';

import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/serialization/landmark_codec.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:path/path.dart' as p;

import 'file_naming.dart';

/// Файлы меток на диске: сохранение, чтение, правка, удаление, перенос.
///
/// Decision: время создания/правки (`created_at`, `updated_at`) и версия
/// хранятся в технических метаданных объекта — это свойства файла, а не
/// то, что пользователь видит и редактирует.
class LandmarkRepository {
  LandmarkRepository(this._service, this._paths, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final StorageService _service;
  final StoragePaths _paths;
  final DateTime Function() _clock;

  /// Сохраняет новый объект и возвращает абсолютный путь файла.
  /// Все типы сохраняются сразу; режим правки — забота UI.
  /// [directory] по умолчанию — [StoragePaths.landmarks]. Ставит
  /// `created_at` и `updated_at` = сейчас.
  Future<String> save(LandmarkFile file, {String? directory}) async {
    final now = _clock();
    final ms = now.millisecondsSinceEpoch;
    final technical = file.content.technicalMetadata.withEntries({
      LandmarkMetadata.createdAtKey: ms,
      LandmarkMetadata.updatedAtKey: ms,
    });
    final stamped = file.withContent(file.content.withTechnicalMetadata(technical));
    final bytes = LandmarkCodec.encode(stamped);

    final dir = directory ?? _paths.landmarks;
    await _ensureDirectory(dir);
    final name = FileNaming.filename(file.content.userMetadata.name ?? '', file.type, at: now);
    final path = await FileNaming.resolveCollision(dir, name);
    await _service.atomicWriteBytes(path, bytes);
    return path;
  }

  /// Читает файл по абсолютному пути.
  Future<LandmarkFile> load(String absolutePath) async => LandmarkCodec.decode(await _service.readBytes(absolutePath));

  /// Перезаписывает существующий файл. Версия технических метаданных —
  /// версия файла на диске + 1, `updated_at` = сейчас, `created_at`
  /// сохраняется с диска.
  Future<void> update(String absolutePath, LandmarkFile file) async {
    final existing = await load(absolutePath);
    final previous = existing.content.technicalMetadata;
    final technical = file.content.technicalMetadata
        .withEntries({
          if (previous.createdAtMs != null) LandmarkMetadata.createdAtKey: previous.createdAtMs,
          LandmarkMetadata.updatedAtKey: _clock().millisecondsSinceEpoch,
        })
        .copyWith(version: previous.version + 1);
    final bytes = LandmarkCodec.encode(file.withContent(file.content.withTechnicalMetadata(technical)));
    await _service.atomicWriteBytes(absolutePath, bytes);
  }

  /// Удаляет файл. Необратимо; отсутствующий файл — не ошибка.
  Future<void> delete(String absolutePath) => _service.deleteFile(absolutePath);

  /// Переносит файл в папку [to] и возвращает новый путь. [newName] —
  /// новое имя файла; без расширения типа оно добавляется. Занятое имя
  /// получает суффикс `_1`, `_2`, ...
  Future<String> move(String from, String to, {String? newName}) async {
    if (!await File(from).exists()) throw StorageException('File to move does not exist', path: from);
    final ext = p.extension(from);
    var name = newName ?? p.basename(from);
    if (ext.isNotEmpty && p.extension(name).toLowerCase() != ext.toLowerCase()) name = '$name$ext';
    final target = p.join(to, name);
    if (p.equals(target, from)) return from;

    await _ensureDirectory(to);
    final path = await FileNaming.resolveCollision(to, name);
    await _service.moveFile(from, path);
    return path;
  }

  /// Абсолютные пути файлов меток в [directory] (не рекурсивно), по алфавиту.
  Future<List<String>> listIn(String directory) async {
    final files = await _service.listFiles(directory, extensions: LandmarkType.extensions);
    return [for (final f in files) f.path];
  }

  Future<void> _ensureDirectory(String dir) async {
    try {
      await Directory(dir).create(recursive: true);
    } on FileSystemException catch (e) {
      throw StorageException('Cannot create folder', path: dir, cause: e);
    }
  }
}
