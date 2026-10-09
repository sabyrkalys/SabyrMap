import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/models/landmark_waypoint.dart';

/// Черновик нового трека.
class TrackDraft {
  const TrackDraft({
    this.name,
    this.comment,
    this.description,
    this.colorValue,
    this.iconId,
    this.targetFolder,
    this.initialLocations = const [],
    this.initialWaypoints = const [],
    this.activity,
    this.autoSplitByTime = false,
    this.splitGapSeconds = defaultSplitGapSeconds,
  });

  /// Разрыв по умолчанию, после которого начинается новый сегмент.
  static const int defaultSplitGapSeconds = 300;

  final String? name;
  final String? comment;
  final String? description;

  /// Цвет ARGB.
  final int? colorValue;
  final String? iconId;

  /// Папка сохранения; null — папка по умолчанию.
  final String? targetFolder;

  /// Точки пути по порядку.
  final List<LandmarkLocation> initialLocations;

  /// Путевые точки, привязанные к треку.
  final List<WaypointObject> initialWaypoints;

  /// Вид активности (пешком, вело...).
  final String? activity;

  /// Делить ли точки на сегменты по паузам во времени (только при
  /// создании). Время — значение `utcTime` точки; без него — один сегмент.
  final bool autoSplitByTime;

  /// Пауза больше этой (секунды) начинает новый сегмент.
  final int splitGapSeconds;

  TrackDraft copyWith({
    String? name,
    String? comment,
    String? description,
    int? colorValue,
    String? iconId,
    String? targetFolder,
    List<LandmarkLocation>? initialLocations,
    List<WaypointObject>? initialWaypoints,
    String? activity,
    bool? autoSplitByTime,
    int? splitGapSeconds,
  }) => TrackDraft(
    name: name ?? this.name,
    comment: comment ?? this.comment,
    description: description ?? this.description,
    colorValue: colorValue ?? this.colorValue,
    iconId: iconId ?? this.iconId,
    targetFolder: targetFolder ?? this.targetFolder,
    initialLocations: initialLocations ?? this.initialLocations,
    initialWaypoints: initialWaypoints ?? this.initialWaypoints,
    activity: activity ?? this.activity,
    autoSplitByTime: autoSplitByTime ?? this.autoSplitByTime,
    splitGapSeconds: splitGapSeconds ?? this.splitGapSeconds,
  );

  /// Общие поля как [MarkerDraft] в точке [anchor].
  MarkerDraft toMarkerDraft(LandmarkLocation anchor) => MarkerDraft(
    type: LandmarkType.track,
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
