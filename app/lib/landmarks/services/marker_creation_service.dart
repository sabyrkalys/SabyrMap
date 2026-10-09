import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:app/landmarks/validation/waypoint_validator.dart';

import 'folder_service.dart';

/// Создание объектов из черновика. В этом спринте — только путевые точки.
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
    final result = WaypointValidator.validate(draft);
    if (!result.isValid) throw ValidationException(result.errors);

    final now = _clock().millisecondsSinceEpoch;
    final name = draft.name?.trim();
    final user = LandmarkMetadata(
      entries: {
        if (name != null && name.isNotEmpty) LandmarkMetadata.nameKey: name,
        if (draft.comment?.trim().isNotEmpty ?? false) LandmarkMetadata.commentKey: draft.comment,
        if (draft.description?.trim().isNotEmpty ?? false) LandmarkMetadata.descriptionKey: draft.description,
        if (draft.colorValue != null) LandmarkMetadata.colorKey: draft.colorValue,
        if (draft.iconId?.isNotEmpty ?? false) LandmarkMetadata.iconKey: draft.iconId,
        LandmarkMetadata.createdAtKey: now,
        LandmarkMetadata.updatedAtKey: now,
      },
    );
    final waypoint = WaypointObject(
      location: LandmarkLocation(longitude: draft.longitude, latitude: draft.latitude),
      userMetadata: user,
    );
    final directory = draft.targetFolder ?? await _folders.getDefaultFolder();
    return _repository.save(LandmarkFile.of(waypoint), directory: directory);
  }
}
