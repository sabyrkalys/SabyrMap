import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/drafts/waypoint_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:app/landmarks/validation/waypoint_validator.dart';

import 'metadata_editor.dart';

/// Чтение, правка, удаление и перенос одной путевой точки.
class WaypointService {
  WaypointService(this._repository, {MetadataEditor editor = const MetadataEditor()}) : _editor = editor;

  final LandmarkRepository _repository;
  final MetadataEditor _editor;

  /// Читает путевую точку. Файл другого типа — [StorageException].
  Future<WaypointObject> load(String absolutePath) async {
    final file = await _repository.load(absolutePath);
    final content = file.content;
    if (content is! WaypointObject) {
      throw StorageException('Not a waypoint file (${file.type.extension})', path: absolutePath);
    }
    return content;
  }

  /// Применяет [patch]: пользовательские метаданные получают version + 1
  /// и новый `updated_at` (даже при пустой правке), координата меняется,
  /// только если она есть в правке. Возвращает точку, как она записана.
  /// Неверная правка — [ValidationException].
  Future<WaypointObject> update(String absolutePath, WaypointPatch patch) async {
    final result = WaypointValidator.validatePatch(patch);
    if (!result.isValid) throw ValidationException(result.errors);

    final current = await load(absolutePath);
    final metadata = _editor.apply(current.userMetadata, metadataPatchOf(patch));
    final location = patch.hasLocation
        ? LandmarkLocation(
            longitude: patch.longitude ?? current.location.longitude,
            latitude: patch.latitude ?? current.location.latitude,
            values: current.location.values,
          )
        : current.location;
    final updated = WaypointObject(
      location: location,
      userMetadata: metadata,
      technicalMetadata: current.technicalMetadata,
    );
    await _repository.update(absolutePath, LandmarkFile.of(updated));
    return load(absolutePath);
  }

  /// Удаляет файл точки; отсутствующий файл — не ошибка.
  Future<void> delete(String absolutePath) => _repository.delete(absolutePath);

  /// Переносит файл в [targetFolder] и возвращает новый путь. [newName] —
  /// желаемое имя: очищается по правилам [FileNaming.baseFromName],
  /// расширение `.wpt` добавляется.
  Future<String> move(String absolutePath, String targetFolder, {String? newName}) => _repository.move(
    absolutePath,
    targetFolder,
    newName: newName == null ? null : '${FileNaming.baseFromName(newName)}.${LandmarkType.waypoint.extension}',
  );

  /// Правка точки как правка метаданных: пустая строка удаляет ключ.
  static MetadataPatch metadataPatchOf(WaypointPatch patch) {
    final set = <String, Object?>{};
    final remove = <String>{};
    void text(String key, String? value) {
      if (value == null) return;
      final cleaned = key == LandmarkMetadata.nameKey ? value.trim() : value;
      if (cleaned.trim().isEmpty) {
        remove.add(key);
      } else {
        set[key] = cleaned;
      }
    }

    text(LandmarkMetadata.nameKey, patch.name);
    text(LandmarkMetadata.commentKey, patch.comment);
    text(LandmarkMetadata.descriptionKey, patch.description);
    text(LandmarkMetadata.iconKey, patch.iconId);
    if (patch.colorValue != null) set[LandmarkMetadata.colorKey] = patch.colorValue;
    for (final MapEntry(:key, :value) in patch.extra.entries) {
      if (value == null) {
        remove.add(key);
        set.remove(key);
      } else {
        set[key] = value;
        remove.remove(key);
      }
    }
    return MetadataPatch(set: set, remove: remove);
  }
}
