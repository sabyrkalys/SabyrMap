import 'dart:io';

import 'package:app/landmarks/import_export/import/import_result.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/landmarks/serialization/landmark_codec.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// «Импорт файла» в папку проводника: выбор файла, прогресс, итог.
///
/// Файлы sabyrmap (`.ldk`, `.wpt`, ...) проверяются и копируются как есть;
/// остальные форматы разбирает [ImportService] — результат: отдельные
/// `.wpt`/`.set`/`.rte`/`.trk`/`.are`.
abstract final class LdkImportFlow {
  /// Выбирает файл системным диалогом и импортирует его в [folder].
  static Future<ImportResult?> start(
    BuildContext context,
    LandmarkServices services,
    String folder,
  ) async {
    final picked = await FilePicker.pickFiles();
    final path = picked?.files.firstOrNull?.path;
    if (path == null || !context.mounted) return null;
    return run(context, services, path, folder);
  }

  /// Импорт [source] в [folder] с окном прогресса; итог — сообщением.
  static Future<ImportResult> run(
    BuildContext context,
    LandmarkServices services,
    String source,
    String folder,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: const Key('ldk_import_progress'),
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text('Импорт «${p.basename(source)}»...')),
            ],
          ),
        ),
      ),
    );
    final ImportResult result;
    try {
      result = await importFile(services, source, folder);
    } finally {
      navigator.pop();
      await progress;
    }
    await services.explorerController.refresh();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Импортировано: ${result.importedCount}'
              : (result.errorMessage ?? 'Импорт не удался'),
        ),
      ),
    );
    return result;
  }

  /// Импорт без UI.
  static Future<ImportResult> importFile(
    LandmarkServices services,
    String source,
    String folder,
  ) async {
    final type = LandmarkType.fromExtension(p.extension(source));
    if (type == null) {
      return services.importService.importFromFile(
        source,
        targetFolder: folder,
      );
    }
    try {
      final bytes = await File(source).readAsBytes();
      final file = LandmarkCodec.decode(bytes);
      await services.folders.ensureFolder(folder);
      final target = await FileNaming.resolveCollision(
        folder,
        p.basename(source),
      );
      await services.storage.atomicWriteBytes(target, bytes);
      await services.repository.changed([target]);
      return ImportResult(
        success: true,
        createdPaths: [target],
        createdTypes: [file.type],
      );
    } on Exception catch (e) {
      return ImportResult.failure(
        'Не удалось импортировать ${p.basename(source)}: $e',
      );
    }
  }
}
