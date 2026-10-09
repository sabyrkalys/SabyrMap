import 'package:app/exceptions/folder_exception.dart';
import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/explorer/clipboard/clipboard_entry.dart';
import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:path/path.dart' as p;

/// Действия меню папки. Возвращают текст для сообщения пользователю;
/// недопустимое действие — «Действие недоступно».
abstract final class FolderContextActions {
  static const String unavailable = 'Действие недоступно';

  /// Закладка на папку.
  static Future<String> bookmark(LandmarkServices s, ExplorerFolderNode folder) async =>
      await s.bookmarkController.addFromFolder(folder.path) ? 'Добавлено в закладки' : 'Уже в закладках';

  /// Копировать и вырезать можно только папки внутри «Мои метки».
  static bool _insideLandmarks(LandmarkServices s, String path) =>
      p.equals(s.paths.landmarks, path) || p.isWithin(s.paths.landmarks, path);

  static String copy(LandmarkServices s, ExplorerFolderNode folder) {
    if (!_insideLandmarks(s, folder.path) || p.equals(s.paths.landmarks, folder.path)) return unavailable;
    s.explorerController.clipboard.copy([ClipboardEntry.folder(sourcePath: folder.path, originalName: folder.name)]);
    return 'Скопировано: ${folder.name}';
  }

  static String cut(LandmarkServices s, ExplorerFolderNode folder) {
    if (!s.folders.isEditable(folder.path)) return unavailable;
    s.explorerController.clipboard.cut([ClipboardEntry.folder(sourcePath: folder.path, originalName: folder.name)]);
    return 'Вырезано: ${folder.name}';
  }

  /// Переименование; то же имя — без изменений (null).
  static Future<String?> rename(LandmarkServices s, ExplorerFolderNode folder, String newName) async {
    if (newName.trim() == folder.name) return null;
    if (!s.folders.isEditable(folder.path)) return unavailable;
    try {
      final newPath = p.join(p.dirname(folder.path), newName.trim());
      await s.folders.rename(folder.path, newPath);
      await s.bookmarkController.updatePath(folder.path, newPath);
      return 'Папка переименована';
    } on FolderException catch (e) {
      return e.message == 'уже существует' ? 'Папка «${newName.trim()}» уже существует' : e.message;
    } on StorageException catch (e) {
      return 'Не удалось переименовать: ${e.message}';
    }
  }

  static Future<String> delete(LandmarkServices s, ExplorerFolderNode folder) async {
    if (!s.folders.isEditable(folder.path)) return unavailable;
    try {
      await s.folders.deleteRecursive(folder.path);
      await s.bookmarkController.removeByPathPrefix(folder.path);
      return 'Папка удалена';
    } on FolderException catch (e) {
      return e.message;
    } on StorageException catch (e) {
      return 'Не удалось удалить: ${e.message}';
    }
  }
}
