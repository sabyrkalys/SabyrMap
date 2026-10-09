import 'dart:io';
import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/composite/validation/composite_validator.dart';
import 'package:app/landmarks/import_export/registry/format_descriptor.dart';
import 'package:app/landmarks/import_export/registry/format_registry.dart';
import 'package:app/landmarks/import_export/utils/elevation_source.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/services/folder_service.dart';
import 'package:app/landmarks/services/metadata_editor.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:path/path.dart' as p;

import 'import_options.dart';
import 'import_request.dart';
import 'import_result.dart';

/// Импорт файлов других форматов в метки sabyrmap. Исходный файл не
/// меняется; каждый найденный объект сохраняется отдельным файлом метки.
class ImportService {
  ImportService(
    this._repository,
    this._folders,
    this._registry,
    this._editor, {
    CompositeCalculator calculator = const CompositeCalculator(),
    DateTime Function()? clock,
  }) : _calculator = calculator,
       _clock = clock ?? DateTime.now;

  final LandmarkRepository _repository;
  final FolderService _folders;
  final FormatRegistry _registry;
  final MetadataEditor _editor;
  final CompositeCalculator _calculator;
  final DateTime Function() _clock;

  /// Импортирует [request]. Файл, который не удалось разобрать, — неудача;
  /// отдельные непрочитанные или неверные объекты — предупреждения.
  Future<ImportResult> import(ImportRequest request) async {
    final adapter = request.format.importAdapter;
    if (adapter == null) return ImportResult.failure('${request.format.displayName} cannot be imported');
    final options = request.options;
    final warnings = <String>[?options.elevation.warning];

    final List<LandmarkObject> objects;
    try {
      objects = await adapter.parse(request.bytes, options, onWarning: warnings.add);
    } on FormatException catch (e) {
      return ImportResult.failure('Cannot read ${p.basename(request.sourcePath)}: ${e.message}', warnings: warnings);
    } on UnsupportedError catch (e) {
      return ImportResult.failure('Cannot read ${p.basename(request.sourcePath)}: ${e.message}', warnings: warnings);
    }
    if (objects.isEmpty) {
      return ImportResult(success: true, warnings: [...warnings, 'No objects found in ${p.basename(request.sourcePath)}']);
    }

    final directory = options.folder ?? request.targetFolder;
    final paths = <String>[];
    final types = <LandmarkType>[];
    for (final (i, object) in objects.indexed) {
      final label = '${object.type.extension} ${i + 1} (${object.userMetadata.name ?? 'untitled'})';
      try {
        final check = CompositeValidator.validateObject(object);
        if (!check.isValid) throw ValidationException(check.errors);
        paths.add(await _repository.save(LandmarkFile.of(_stamp(object)), directory: directory));
        types.add(object.type);
      } on ValidationException catch (e) {
        warnings.add('$label: ${e.errors.join('; ')}, skipped');
      } on SerializationException catch (e) {
        warnings.add('$label: ${e.message}, skipped');
      } on StorageException catch (e) {
        warnings.add('$label: ${e.message}, skipped');
      }
    }
    return ImportResult(
      success: paths.isNotEmpty,
      createdPaths: paths,
      createdTypes: types,
      warnings: warnings,
      errorMessage: paths.isEmpty ? 'No object could be imported' : null,
    );
  }

  /// Опции по умолчанию из схемы формата.
  Future<ImportOptions> defaultOptions(FormatDescriptor format) async {
    final defaults = format.importAdapter?.optionsSchema.defaults ?? const <String, Object?>{};
    return ImportOptions(
      elevation: defaults.containsKey('elevationSource')
          ? ElevationSource.parse(defaults['elevationSource'])
          : ElevationSource.wgs84,
      extras: defaults,
    );
  }

  /// Импорт файла с диска: формат по расширению, опции по умолчанию,
  /// папка по умолчанию.
  Future<ImportResult> importFromFile(String path, {String? targetFolder, ImportOptions? options}) async {
    final format = _registry.byExtension(p.extension(path));
    if (format == null) return ImportResult.failure('Unknown file format: ${p.basename(path)}');
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      return ImportResult.failure('Cannot read $path: ${e.message}');
    }
    return import(
      ImportRequest(
        bytes: bytes,
        sourcePath: path,
        format: format,
        options: options ?? await defaultOptions(format),
        targetFolder: targetFolder ?? await _folders.getDefaultFolder(),
      ),
    );
  }

  /// Пользовательские метаданные нового файла: статистика, created_at /
  /// updated_at (если в источнике не было), версия 0.
  LandmarkObject _stamp(LandmarkObject object) {
    final now = _clock().millisecondsSinceEpoch;
    final stats = _calculator.metadataFor(object);
    final entries = <String, dynamic>{
      ...object.userMetadata.entries,
      for (final MapEntry(:key, :value) in stats.set.entries) key: value,
    }..removeWhere((key, _) => stats.remove.contains(key));
    entries.putIfAbsent(LandmarkMetadata.createdAtKey, () => now);
    entries.putIfAbsent(LandmarkMetadata.updatedAtKey, () => now);
    final metadata = LandmarkMetadata(entries: entries);
    _editor.validateEntries(metadata);
    return object.withUserMetadata(metadata);
  }
}
