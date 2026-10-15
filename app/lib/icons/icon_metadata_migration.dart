import 'dart:io';

import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_metadata.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'waypoint_icon_store.dart';

/// Однократный перенос значков из библиотеки, назначенных точкам, из
/// защищённого хранилища (ключ — путь `.wpt`) в сами файлы
/// (`user_icon`).
///
/// Decision:
/// - ключи записаны со старыми путями: до 14.10 метки лежали в
///   `files/landmarks/`, теперь — в `files/mediafile/landmarks/`; путь
///   пересчитывается с подпапками;
/// - запись удаляется из хранилища только после записи в файл; не найденный
///   файл (и объект внутри `.ldk`) остаётся в хранилище и в логе, а не
///   пропадает молча;
/// - флаг ставится после прохода — повторно миграция не запускается.
abstract final class IconMetadataMigration {
  static const String doneKey = 'migration.icon_to_metadata_v1';

  /// Переносит значки из [legacy]; возвращает ключи, для которых файл не
  /// нашёлся. Уже выполненная миграция — пусто, без чтения хранилища.
  static Future<List<String>> run(LandmarkServices services, WaypointIconStore legacy) async {
    if (services.settings.getString(doneKey) != null) return const [];
    final orphans = <String>[];
    for (final MapEntry(key: id, value: icon) in (await legacy.readAll()).entries) {
      final path = await locate(services.paths, id);
      if (path == null) {
        orphans.add(id);
        continue;
      }
      try {
        await services.patchMetadata(path, MetadataPatch(set: {LandmarkMetadata.userIconKey: icon}));
        await legacy.setIcon(id, null);
      } on Exception catch (e) {
        debugPrint('sabyrmap: значок $icon для $path не перенесён: $e');
        orphans.add(id);
      }
    }
    await services.settings.setString(doneKey, DateTime.now().toIso8601String());
    if (orphans.isNotEmpty) debugPrint('sabyrmap: значки без файла остались в хранилище: $orphans');
    return orphans;
  }

  /// Файл точки по старому ключу: как есть или перенесённый в
  /// `mediafile/landmarks` с теми же подпапками; null — не найден или это
  /// объект внутри файла меток.
  @visibleForTesting
  static Future<String?> locate(StoragePaths paths, String id) async {
    if (LandmarkItem.fileOf(id) != id) return null;
    if (await File(id).exists()) return id;
    if (p.basename(paths.appRoot) != StoragePaths.mediafileFolderName) return null;
    final legacyRoot = p.join(p.dirname(paths.appRoot), 'landmarks');
    if (!p.isWithin(legacyRoot, id)) return null;
    final moved = p.join(paths.landmarks, p.relative(id, from: legacyRoot));
    return await File(moved).exists() ? moved : null;
  }
}
