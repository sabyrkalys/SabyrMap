import 'dart:convert';

import 'package:app/exceptions/folder_exception.dart';
import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/explorer/clipboard/clipboard_entry.dart';
import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// Действия меню папки. Возвращают текст для сообщения пользователю;
/// недопустимое действие — «Действие недоступно».
abstract final class FolderContextActions {
  static const String unavailable = 'Действие недоступно';

  /// Закладки — список путей в настройках.
  static List<String> bookmarks(LandmarkServices s) {
    final raw = s.settings.getString(SettingsKeys.explorerBookmarks);
    if (raw == null) return const [];
    try {
      return [for (final v in jsonDecode(raw) as List<dynamic>) v as String];
    } on Object {
      return const [];
    }
  }

  static Future<String> bookmark(LandmarkServices s, ExplorerFolderNode folder) async {
    final list = bookmarks(s);
    if (list.contains(folder.path)) return 'Уже в закладках';
    await _saveBookmarks(s, [...list, folder.path]);
    return 'Добавлено в закладки';
  }

  /// Убирает закладку [path].
  static Future<void> removeBookmark(LandmarkServices s, String path) =>
      _saveBookmarks(s, [...bookmarks(s).where((b) => b != path)]);

  /// После переименования или удаления папки: закладки на неё и на папки
  /// внутри неё переезжают на [newPath] или удаляются (null).
  static Future<void> _moveBookmarks(LandmarkServices s, String oldPath, String? newPath) async {
    final list = bookmarks(s);
    final updated = <String>[
      for (final b in list)
        if (p.equals(b, oldPath) || p.isWithin(oldPath, b))
          if (newPath != null) p.normalize(p.join(newPath, p.relative(b, from: oldPath))) else ...[]
        else
          b,
    ];
    if (updated.length != list.length || !const ListEquality<String>().equals(updated, list)) {
      await _saveBookmarks(s, updated);
    }
  }

  static Future<void> _saveBookmarks(LandmarkServices s, List<String> list) =>
      s.settings.setString(SettingsKeys.explorerBookmarks, jsonEncode(list));

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
      await _moveBookmarks(s, folder.path, newPath);
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
      await _moveBookmarks(s, folder.path, null);
      return 'Папка удалена';
    } on FolderException catch (e) {
      return e.message;
    } on StorageException catch (e) {
      return 'Не удалось удалить: ${e.message}';
    }
  }
}
