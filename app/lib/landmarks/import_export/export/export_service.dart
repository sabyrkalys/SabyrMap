import 'dart:io';
import 'dart:typed_data';

import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/import_export/registry/format_capability.dart';
import 'package:app/landmarks/import_export/registry/format_descriptor.dart';
import 'package:app/landmarks/import_export/registry/format_registry.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/services/folder_service.dart';
import 'package:path/path.dart' as p;

import 'export_options.dart';
import 'export_request.dart';
import 'export_result.dart';

/// Экспорт меток в файл другого формата. Сами метки не меняются.
class ExportService {
  ExportService(this._repository, this._folders, this._registry, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LandmarkRepository _repository;
  final FolderService _folders;
  final FormatRegistry _registry;
  final DateTime Function() _clock;

  /// Имя файла, если объектов несколько и имя не задано.
  static const String multiObjectBaseName = 'landmarks';

  /// Все подходящие объекты — в один файл в [ExportRequest.targetFolder];
  /// занятое имя получает `_1`, `_2`. Объекты типов, которые формат не
  /// умеет, пропускаются с предупреждением.
  Future<ExportResult> export(ExportRequest request) async {
    final format = request.format;
    final adapter = format.exportAdapter;
    if (adapter == null) return ExportResult.failure('${format.displayName} cannot be exported');

    final warnings = <String>[];
    final objects = <LandmarkObject>[];
    final skipped = <LandmarkType>{};
    for (final object in request.objects) {
      if (format.supports(FormatCapability.exportOf(object.type))) {
        objects.add(object);
      } else if (skipped.add(object.type)) {
        warnings.add('${format.displayName} does not support ${object.type.extension} objects; skipped');
      }
    }
    if (objects.isEmpty) {
      return ExportResult.failure('Nothing to export to ${format.displayName}', warnings: warnings);
    }
    if (objects.length > 1 && !format.supports(FormatCapability.multiObjectPerFile)) {
      return ExportResult.failure('${format.displayName} holds one object per file', warnings: warnings);
    }

    final Uint8List bytes;
    try {
      bytes = await adapter.serialize(objects, request.options, onWarning: warnings.add);
    } on FormatException catch (e) {
      return ExportResult.failure('Cannot write ${format.displayName}: ${e.message}', warnings: warnings);
    }

    final ext = adapter.extensionFor(request.options);
    final name = _filename(request.preferredFilename, objects, ext);
    try {
      await Directory(request.targetFolder).create(recursive: true);
      final path = await FileNaming.resolveCollision(request.targetFolder, name);
      await _repository.storage.atomicWriteBytes(path, bytes);
      return ExportResult(success: true, filePath: path, exportedCount: objects.length, warnings: warnings);
    } on FileSystemException catch (e) {
      return ExportResult.failure('Cannot create ${request.targetFolder}: ${e.message}', warnings: warnings);
    } on StorageException catch (e) {
      return ExportResult.failure(e.message, warnings: warnings);
    }
  }

  /// Опции по умолчанию из схемы формата.
  Future<ExportOptions> defaultOptions(FormatDescriptor format) async {
    final defaults = format.exportAdapter?.optionsSchema.defaults ?? const <String, Object?>{};
    return ExportOptions(
      includeWaypoints: defaults['includeWaypoints'] as bool? ?? true,
      includeSegments: defaults['includeSegments'] as bool? ?? true,
      extras: defaults,
    );
  }

  /// Экспорт файлов меток [sourcePaths] в формат [formatId] с опциями по
  /// умолчанию. Decision: без [targetFolder] файл кладётся в папку меток по
  /// умолчанию. Непрочитанные файлы — предупреждения.
  Future<ExportResult> exportToFile(List<String> sourcePaths, String formatId, {String? targetFolder}) async {
    final format = _registry.byId(formatId);
    if (format == null) return ExportResult.failure('Unknown format: $formatId');
    final objects = <LandmarkObject>[];
    final warnings = <String>[];
    for (final path in sourcePaths) {
      try {
        objects.add((await _repository.load(path)).content);
      } on Exception catch (e) {
        warnings.add('${p.basename(path)}: cannot be read ($e), skipped');
      }
    }
    final result = await export(
      ExportRequest(
        objects: objects,
        format: format,
        options: await defaultOptions(format),
        targetFolder: targetFolder ?? await _folders.getDefaultFolder(),
      ),
    );
    return ExportResult(
      success: result.success,
      filePath: result.filePath,
      exportedCount: result.exportedCount,
      errorMessage: result.errorMessage,
      warnings: [...warnings, ...result.warnings],
    );
  }

  /// Заданное имя (только имя файла, с расширением формата) или
  /// `<имя объекта>_<время>.<ext>`.
  String _filename(String? preferred, List<LandmarkObject> objects, String ext) {
    if (preferred != null && preferred.trim().isNotEmpty) {
      final base = p.basename(preferred.trim());
      return p.extension(base).toLowerCase() == '.$ext' ? base : '$base.$ext';
    }
    final name = objects.length == 1 ? objects.single.userMetadata.name ?? '' : multiObjectBaseName;
    return '${FileNaming.baseFromName(name)}_${_clock().millisecondsSinceEpoch}.$ext';
  }
}
