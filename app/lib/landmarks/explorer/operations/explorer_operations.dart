import 'dart:io';

import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/explorer/clipboard/clipboard_entry.dart';
import 'package:app/landmarks/explorer/clipboard/landmarks_clipboard.dart';
import 'package:app/landmarks/explorer/display/display_registry.dart';
import 'package:app/landmarks/explorer/listing/landmark_item_reader.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/services/metadata_editor.dart';
import 'package:app/storage/storage_service.dart';
import 'package:path/path.dart' as p;

import 'operation_result.dart';

/// Операции проводника над одной меткой или выбранной группой. Ошибка с
/// одним файлом не останавливает остальные: она попадает в
/// [OperationResult.errorMessage], а успешные считаются в
/// [OperationResult.affectedCount].
class ExplorerOperations {
  ExplorerOperations({
    required LandmarkRepository repository,
    required LandmarkItemReader reader,
    required StorageService storage,
    required LandmarksClipboard clipboard,
    required DisplayRegistry display,
    MetadataEditor editor = const MetadataEditor(),
  }) : _repository = repository,
       _reader = reader,
       _storage = storage,
       _clipboard = clipboard,
       _display = display,
       _editor = editor;

  final LandmarkRepository _repository;
  final LandmarkItemReader _reader;
  final StorageService _storage;
  final LandmarksClipboard _clipboard;
  final DisplayRegistry _display;
  final MetadataEditor _editor;

  /// Ключи, которые меняет [editDetailsSelected] в этом спринте.
  static const Set<String> editableKeys = {
    LandmarkMetadata.nameKey,
    LandmarkMetadata.colorKey,
    LandmarkMetadata.iconKey,
  };

  /// Удаляет файл метки, предварительно убрав его с карты.
  Future<OperationResult> deleteOne(String path) => deleteSelected({path});

  /// Удаляет файлы меток. Decision: путь, которого нет или который не
  /// файл метки, — ошибка (проводник показывает только существующие).
  Future<OperationResult> deleteSelected(Set<String> paths) => _each(paths, (path) async {
    await _requireLandmarkFile(path);
    _display.undisplay(path);
    await _repository.delete(path);
  });

  /// Показывает файлы на карте; файлы не трогает.
  Future<OperationResult> displaySelected(Set<String> paths) async {
    _display.displayAll(paths);
    return OperationResult.ok(paths.length);
  }

  /// Убирает файлы с карты; файлы не трогает.
  Future<OperationResult> undisplaySelected(Set<String> paths) async {
    _display.undisplayAll(paths);
    return OperationResult.ok(paths.length);
  }

  /// Кладёт файлы в буфер для копирования. Нечитаемые не попадают в буфер
  /// и считаются ошибкой.
  Future<OperationResult> copySelected(Set<String> paths) => _toClipboard(paths, cut: false);

  /// Кладёт файлы в буфер для переноса.
  Future<OperationResult> cutSelected(Set<String> paths) => _toClipboard(paths, cut: true);

  /// Вставляет весь буфер в [targetFolder]. Занятые имена получают `_1`,
  /// `_2`, ... Вырезанные файлы переносятся и уходят из буфера;
  /// скопированные остаются в буфере для повторной вставки.
  Future<OperationResult> pasteAll(String targetFolder) async {
    if (_clipboard.isEmpty) return OperationResult.ok(0);
    final entries = List.of(_clipboard.entries);
    return _each([for (final e in entries) e.sourcePath], (source) async {
      await _paste(targetFolder, entries.firstWhere((e) => e.sourcePath == source));
    });
  }

  /// Вставляет одну запись буфера.
  Future<OperationResult> pasteOne(String targetFolder, String sourcePath) async {
    final entry = _clipboard.entries.where((e) => e.sourcePath == sourcePath).firstOrNull;
    if (entry == null) return OperationResult.failed('$sourcePath is not in the clipboard');
    return _each([sourcePath], (_) => _paste(targetFolder, entry));
  }

  /// Правит метаданные всех [paths] одним патчем ([MetadataEditor.apply]:
  /// version + 1, `updated_at`). В этом спринте — только [editableKeys].
  Future<OperationResult> editDetailsSelected(Set<String> paths, MetadataPatch patch) async {
    final unsupported = {...patch.set.keys, ...patch.remove}.difference(editableKeys);
    if (unsupported.isNotEmpty) {
      return OperationResult.failed('Unsupported metadata keys: ${(unsupported.toList()..sort()).join(', ')}');
    }
    return _each(paths, (path) async {
      final file = await _repository.load(path);
      final metadata = _editor.apply(file.content.userMetadata, patch);
      await _repository.update(path, file.withContent(file.content.withUserMetadata(metadata)));
    });
  }

  Future<OperationResult> _toClipboard(Set<String> paths, {required bool cut}) async {
    final entries = <ClipboardEntry>[];
    final errors = <String>[];
    for (final path in paths) {
      final item = await _reader.read(path);
      if (item == null) {
        errors.add('$path: not a readable landmark file');
        continue;
      }
      entries.add(ClipboardEntry(sourcePath: path, type: item.type, originalName: item.name));
    }
    cut ? _clipboard.cut(entries) : _clipboard.copy(entries);
    return OperationResult.of(entries.length, errors);
  }

  /// Decision: вырезанный файл, вставленный в свою же папку, остаётся на
  /// месте (это не ошибка); скопированный — получает копию с суффиксом.
  Future<void> _paste(String targetFolder, ClipboardEntry entry) async {
    final source = entry.sourcePath;
    await _requireLandmarkFile(source);
    await Directory(targetFolder).create(recursive: true);
    if (_clipboard.isCut) {
      if (!p.equals(p.dirname(source), targetFolder)) {
        final target = await FileNaming.resolveCollision(targetFolder, p.basename(source));
        await _storage.moveFile(source, target);
        if (_display.isDisplayed(source)) {
          _display.undisplay(source);
          _display.display(target);
        }
      }
      _clipboard.removeOne(source);
    } else {
      final target = await FileNaming.resolveCollision(targetFolder, p.basename(source));
      await _storage.atomicWriteBytes(target, await _storage.readBytes(source));
    }
  }

  static Future<void> _requireLandmarkFile(String path) async {
    if (LandmarkType.fromExtension(p.extension(path)) == null) {
      throw FileSystemException('not a landmark file', path);
    }
    if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file) {
      throw FileSystemException('file not found', path);
    }
  }

  static Future<OperationResult> _each(Iterable<String> paths, Future<void> Function(String path) action) async {
    var done = 0;
    final errors = <String>[];
    for (final path in paths) {
      try {
        await action(path);
        done++;
      } on Exception catch (e) {
        errors.add('$path: ${_describe(e)}');
      }
    }
    return OperationResult.of(done, errors);
  }

  static String _describe(Exception e) => switch (e) {
    FileSystemException(:final message) => message,
    _ => e.toString(),
  };
}
