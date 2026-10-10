import 'package:app/exceptions/folder_exception.dart';
import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/explorer/clipboard/clipboard_entry.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:path/path.dart' as p;

import 'ldk_properties_dialog.dart';

/// Итог переименования: новый путь (null — не удалось) и текст сообщения.
typedef LdkRenameResult = ({String? path, String message});

/// Действия над файлом меток. Возвращают текст для сообщения пользователю.
abstract final class LdkContextActions {
  /// Имя файла: из метаданных или имя на диске без расширения.
  static String displayName(LandmarkFile? file, String path) {
    final name = file?.content.userMetadata.name?.trim();
    return name != null && name.isNotEmpty
        ? name
        : p.basenameWithoutExtension(path);
  }

  /// Свойства файла для диалога.
  static LdkProperties propertiesOf(LandmarkFile file, String path) {
    final m = file.content.userMetadata;
    return LdkProperties(
      name: displayName(file, path),
      comment: m.entries[LandmarkMetadata.commentKey] as String? ?? '',
      description: m.entries[LandmarkMetadata.descriptionKey] as String? ?? '',
    );
  }

  /// Переименование: новое имя пишется в метаданные, файл получает имя из
  /// него (занятое — с `_1`, `_2`). Показ на карте и буфер следуют за файлом.
  /// То же имя — без изменений (null).
  static Future<LdkRenameResult?> rename(
    LandmarkServices s,
    String path,
    String newName,
  ) async {
    final name = newName.trim();
    try {
      final file = await s.repository.load(path);
      if (name.isEmpty || name == displayName(file, path)) return null;
      final user = s.editor.apply(
        file.content.userMetadata,
        MetadataPatch(set: {LandmarkMetadata.nameKey: name}),
      );
      await s.repository.update(
        path,
        file.withContent(file.content.withUserMetadata(user)),
      );
      final renamed = await s.folders.renameFile(
        path,
        FileNaming.baseFromName(name),
      );
      _follow(s, path, renamed);
      return (path: renamed, message: 'Файл переименован');
    } on FolderException catch (e) {
      return (path: null, message: e.message);
    } on StorageException catch (e) {
      return (path: null, message: 'Не удалось переименовать: ${e.message}');
    } on Exception catch (e) {
      return (path: null, message: 'Не удалось переименовать: $e');
    }
  }

  /// Новые имя, комментарий и описание; пустое значение удаляет ключ.
  /// Версия метаданных растёт.
  static Future<String> updateProperties(
    LandmarkServices s,
    String path,
    LdkProperties props,
  ) async {
    try {
      final file = await s.repository.load(path);
      String? orNull(String v) => v.trim().isEmpty ? null : v.trim();
      final user = s.editor.apply(
        file.content.userMetadata,
        MetadataPatch(
          set: {
            LandmarkMetadata.nameKey: orNull(props.name),
            LandmarkMetadata.commentKey: orNull(props.comment),
            LandmarkMetadata.descriptionKey: orNull(props.description),
          },
        ),
      );
      await s.repository.update(
        path,
        file.withContent(file.content.withUserMetadata(user)),
      );
      return 'Свойства обновлены';
    } on Exception catch (e) {
      return 'Не удалось обновить свойства: $e';
    }
  }

  /// Удаление файла (с карты и из буфера он тоже уходит).
  static Future<String> delete(LandmarkServices s, String path) async {
    final result = await s.explorerOperations.deleteOne(path);
    return result.success
        ? 'Файл удалён'
        : (result.errorMessage ?? 'Не удалось удалить');
  }

  /// Показать или скрыть на карте; true — теперь показан.
  static bool toggleDisplay(LandmarkServices s, String path) =>
      s.displayRegistry.toggle(path);

  static String copy(LandmarkServices s, String path, String name) {
    s.explorerController.clipboard.copy([
      ClipboardEntry(
        sourcePath: path,
        type: LandmarkType.ldkFile,
        originalName: name,
      ),
    ]);
    return 'Скопировано: $name';
  }

  static String cut(LandmarkServices s, String path, String name) {
    s.explorerController.clipboard.cut([
      ClipboardEntry(
        sourcePath: path,
        type: LandmarkType.ldkFile,
        originalName: name,
      ),
    ]);
    return 'Вырезано: $name';
  }

  /// Включает выбор и отмечает файл.
  static void select(LandmarkServices s, String path) {
    s.explorerController.selection
      ..activate()
      ..select(path);
  }

  /// Отправка файла; null — передан системе.
  static Future<String?> share(LandmarkServices s, String path) async {
    try {
      await s.shareService.shareFile(path);
      return null;
    } on UnsupportedError {
      return 'Отправка файлов на этом устройстве недоступна';
    } on Exception catch (e) {
      return 'Не удалось отправить: $e';
    }
  }

  static void _follow(LandmarkServices s, String from, String to) {
    if (from == to) return;
    final display = s.displayRegistry;
    if (display.isDisplayed(from)) {
      display
        ..undisplay(from)
        ..display(to);
    }
    s.explorerController.clipboard.removeOne(from);
  }
}
