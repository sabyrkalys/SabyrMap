import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_type.dart';

/// Черновик новой области.
class AreaDraft {
  const AreaDraft({
    this.name,
    this.comment,
    this.description,
    this.colorValue,
    this.iconId,
    this.targetFolder,
    this.initialOutline = const [],
    this.isClosed = true,
  });

  final String? name;
  final String? comment;
  final String? description;

  /// Цвет ARGB.
  final int? colorValue;
  final String? iconId;

  /// Папка сохранения; null — папка по умолчанию.
  final String? targetFolder;

  /// Контур, без повтора первой точки в конце.
  final List<LandmarkLocation> initialOutline;

  /// Замкнут ли контур. Незамкнутый: площадь 0, периметр — по ломаной.
  final bool isClosed;

  AreaDraft copyWith({
    String? name,
    String? comment,
    String? description,
    int? colorValue,
    String? iconId,
    String? targetFolder,
    List<LandmarkLocation>? initialOutline,
    bool? isClosed,
  }) => AreaDraft(
    name: name ?? this.name,
    comment: comment ?? this.comment,
    description: description ?? this.description,
    colorValue: colorValue ?? this.colorValue,
    iconId: iconId ?? this.iconId,
    targetFolder: targetFolder ?? this.targetFolder,
    initialOutline: initialOutline ?? this.initialOutline,
    isClosed: isClosed ?? this.isClosed,
  );

  /// Общие поля как [MarkerDraft] в точке [anchor].
  MarkerDraft toMarkerDraft(LandmarkLocation anchor) => MarkerDraft(
    type: LandmarkType.area,
    longitude: anchor.longitude,
    latitude: anchor.latitude,
    name: name,
    comment: comment,
    description: description,
    colorValue: colorValue,
    iconId: iconId,
    targetFolder: targetFolder,
  );
}
