import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:app/landmarks/validation/waypoint_validator.dart';

import 'folder_service.dart';

/// Создание объектов из черновика: путевые точки и файлы меток (`.ldk`).
///
/// Decision: вместо [StoragePaths] принимает [FolderService] — папка по
/// умолчанию берётся из него (с учётом настройки).
class MarkerCreationService {
  MarkerCreationService(this._repository, this._folders, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LandmarkRepository _repository;
  final FolderService _folders;
  final DateTime Function() _clock;

  /// Проверяет черновик, сохраняет объект и возвращает абсолютный путь.
  /// Неверный черновик — [ValidationException], файл не создаётся.
  Future<String> create(MarkerDraft draft) async {
    final isFile = draft.type == LandmarkType.ldkFile;
    // Файл меток проверяется как точка (длины полей), но без координат.
    final result = WaypointValidator.validate(isFile ? draft.copyWith(type: LandmarkType.waypoint) : draft);
    if (!result.isValid) throw ValidationException(result.errors);

    final now = _clock().millisecondsSinceEpoch;
    final name = draft.name?.trim();
    final user = LandmarkMetadata(
      entries: {
        ...draft.extraMetadata,
        if (name != null && name.isNotEmpty) LandmarkMetadata.nameKey: name,
        if (draft.comment?.trim().isNotEmpty ?? false) LandmarkMetadata.commentKey: draft.comment,
        if (draft.description?.trim().isNotEmpty ?? false) LandmarkMetadata.descriptionKey: draft.description,
        if (draft.colorValue != null) LandmarkMetadata.colorKey: draft.colorValue,
        if (draft.iconId?.isNotEmpty ?? false) LandmarkMetadata.iconKey: draft.iconId,
        LandmarkMetadata.createdAtKey: now,
        LandmarkMetadata.updatedAtKey: now,
      },
    );
    final at = LandmarkLocation(longitude: draft.longitude, latitude: draft.latitude);
    final LandmarkObject object = switch (draft.type) {
      LandmarkType.ldkFile => LdkFileObject(userMetadata: user),
      LandmarkType.circle => CircleObject(center: at, radiusMeters: draft.radiusMeters!, userMetadata: user),
      LandmarkType.text => TextObject(location: at, text: draft.text!.trim(), userMetadata: user),
      _ => WaypointObject(location: at, userMetadata: user),
    };
    final directory = draft.targetFolder ?? await _folders.getDefaultFolder();
    return _repository.save(LandmarkFile.of(object), directory: directory);
  }
}
