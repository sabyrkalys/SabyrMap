import 'dart:async';

import 'package:app/exceptions/folder_exception.dart';
import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/explorer/clipboard/clipboard_entry.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../dialogs/landmark_properties_dialog.dart';

/// Итог переименования: новый путь (null — не удалось) и текст сообщения.
typedef RenameResult = ({String? path, String message});

/// Операции над одним файлом метки для меню и детализации. Возвращают
/// текст сообщения пользователю.
abstract final class ItemActions {
  /// Сообщение заглушки.
  static const String notYet = 'Эта функция пока недоступна';

  /// Имя объекта: из метаданных или имя файла без расширения.
  static String displayName(LandmarkFile? file, String path) {
    final name = file?.content.userMetadata.name?.trim();
    return name != null && name.isNotEmpty ? name : p.basenameWithoutExtension(path);
  }

  /// Имя, комментарий и описание для диалога свойств.
  static LandmarkProperties propertiesOf(LandmarkFile file, String path) {
    final m = file.content.userMetadata;
    return LandmarkProperties(
      name: displayName(file, path),
      comment: m.entries[LandmarkMetadata.commentKey] as String? ?? '',
      description: m.entries[LandmarkMetadata.descriptionKey] as String? ?? '',
    );
  }

  /// Правка пользовательских метаданных файла (версия растёт).
  static Future<void> _patch(LandmarkServices s, String path, MetadataPatch patch) async {
    final file = await s.repository.load(path);
    final user = s.editor.apply(file.content.userMetadata, patch);
    await s.repository.update(path, file.withContent(file.content.withUserMetadata(user)));
  }

  /// Переименование: новое имя пишется в метаданные, файл получает имя из
  /// него (занятое — с `_1`, `_2`). Показ на карте и буфер следуют за
  /// файлом. То же имя — без изменений (null).
  static Future<RenameResult?> rename(LandmarkServices s, String path, String newName) async {
    final name = newName.trim();
    try {
      final file = await s.repository.load(path);
      if (name.isEmpty || name == displayName(file, path)) return null;
      await _patch(s, path, MetadataPatch(set: {LandmarkMetadata.nameKey: name}));
      final renamed = await s.folders.renameFile(path, FileNaming.baseFromName(name));
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
  static Future<String> updateProperties(LandmarkServices s, String path, LandmarkProperties props) async {
    String? orNull(String v) => v.trim().isEmpty ? null : v.trim();
    try {
      await _patch(
        s,
        path,
        MetadataPatch(
          set: {
            LandmarkMetadata.nameKey: orNull(props.name),
            LandmarkMetadata.commentKey: orNull(props.comment),
            LandmarkMetadata.descriptionKey: orNull(props.description),
          },
        ),
      );
      return 'Свойства обновлены';
    } on Exception catch (e) {
      return 'Не удалось обновить свойства: $e';
    }
  }

  /// Новый цвет (ARGB).
  static Future<String> setColor(LandmarkServices s, String path, int color) async {
    try {
      await _patch(s, path, MetadataPatch(set: {LandmarkMetadata.colorKey: color}));
      return 'Цвет изменён';
    } on Exception catch (e) {
      return 'Не удалось изменить цвет: $e';
    }
  }

  /// Удаление файла (с карты и из буфера он тоже уходит).
  static Future<String> delete(LandmarkServices s, String path) async {
    final result = await s.explorerOperations.deleteOne(path);
    return result.success ? 'Файл удалён' : (result.errorMessage ?? 'Не удалось удалить');
  }

  /// Показать или скрыть на карте; true — теперь показан.
  static bool toggleDisplay(LandmarkServices s, String path) => s.displayRegistry.toggle(path);

  static String copy(LandmarkServices s, LandmarkItem item) {
    s.explorerController.clipboard.copy([ClipboardEntry(sourcePath: item.path, type: item.type, originalName: item.name)]);
    return 'Скопировано: ${item.name}';
  }

  static String cut(LandmarkServices s, LandmarkItem item) {
    s.explorerController.clipboard.cut([ClipboardEntry(sourcePath: item.path, type: item.type, originalName: item.name)]);
    return 'Вырезано: ${item.name}';
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

  /// Ставит путевую точку целью навигации и возвращает её координату.
  ///
  /// Decision: сведения о цели считаются от положения устройства, а его
  /// получение может ждать спутников — поэтому не ждём, меню закрывается
  /// сразу.
  static Future<LandmarkLocation> setTarget(LandmarkServices s, String path) async {
    final location = (await s.waypoints.load(path)).location;
    unawaited(s.targetController.setTarget(location));
    return location;
  }

  /// Обратный порядок точек маршрута.
  static Future<String> reverseRoute(LandmarkServices s, String path) async {
    try {
      await s.routeService.mutate(
        path,
        (o) => RouteObject(
          waypoints: o.waypoints.reversed.toList(),
          userMetadata: o.userMetadata,
          technicalMetadata: o.technicalMetadata,
        ),
      );
      return 'Порядок точек изменён';
    } on Exception catch (e) {
      return 'Не удалось изменить порядок: $e';
    }
  }

  /// Замыкает или размыкает контур области; true — теперь замкнут.
  static Future<bool> toggleClosed(LandmarkServices s, String path) async {
    final area = await s.areaService.load(path);
    final closed = !CompositeCalculator.isClosed(area);
    await s.areaService.updateMetadata(path, MetadataPatch(set: {LandmarkMetadata.closedKey: closed}));
    return closed;
  }

  /// Заглушка действия, которого ещё нет: запись в лог и сообщение.
  static String stub(String action, String path) {
    debugPrint('sabyrmap: «$action» для ${p.basename(path)} — пока заглушка');
    return notYet;
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
