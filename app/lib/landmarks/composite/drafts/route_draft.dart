import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_type.dart';

/// Черновик нового маршрута.
class RouteDraft {
  const RouteDraft({
    this.name,
    this.comment,
    this.description,
    this.colorValue,
    this.iconId,
    this.targetFolder,
    this.initialWaypoints = const [],
  });

  final String? name;
  final String? comment;
  final String? description;

  /// Цвет ARGB.
  final int? colorValue;
  final String? iconId;

  /// Папка сохранения; null — папка по умолчанию.
  final String? targetFolder;

  /// Точки маршрута в порядке обхода; каждая станет путевой точкой без имени.
  final List<LandmarkLocation> initialWaypoints;

  RouteDraft copyWith({
    String? name,
    String? comment,
    String? description,
    int? colorValue,
    String? iconId,
    String? targetFolder,
    List<LandmarkLocation>? initialWaypoints,
  }) => RouteDraft(
    name: name ?? this.name,
    comment: comment ?? this.comment,
    description: description ?? this.description,
    colorValue: colorValue ?? this.colorValue,
    iconId: iconId ?? this.iconId,
    targetFolder: targetFolder ?? this.targetFolder,
    initialWaypoints: initialWaypoints ?? this.initialWaypoints,
  );

  /// Общие поля как [MarkerDraft] в точке [anchor].
  MarkerDraft toMarkerDraft(LandmarkLocation anchor) => MarkerDraft(
    type: LandmarkType.route,
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
