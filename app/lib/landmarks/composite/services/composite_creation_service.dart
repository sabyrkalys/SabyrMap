import 'package:app/landmarks/composite/drafts/area_draft.dart';
import 'package:app/landmarks/composite/drafts/route_draft.dart';
import 'package:app/landmarks/composite/drafts/set_draft.dart';
import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/composite/validation/composite_validator.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/landmarks/services/folder_service.dart';
import 'package:app/landmarks/services/metadata_editor.dart';
import 'package:app/landmarks/validation/validation_result.dart';

/// Создание набора, маршрута, трека и области из черновика.
///
/// Decision: [anchor] — точка на карте, где пользователь начал создание.
/// Если у набора, маршрута или области в черновике нет точек, [anchor]
/// становится первой точкой; трек может быть пустым и остаётся пустым.
class CompositeCreationService {
  CompositeCreationService(
    this._repository,
    this._folders,
    this._editor, {
    CompositeCalculator calculator = const CompositeCalculator(),
    DateTime Function()? clock,
  }) : _calculator = calculator,
       _clock = clock ?? DateTime.now;

  final LandmarkRepository _repository;
  final FolderService _folders;
  final MetadataEditor _editor;
  final CompositeCalculator _calculator;
  final DateTime Function() _clock;

  Future<String> createSet(SetDraft draft, LandmarkLocation anchor) async {
    _check(CompositeValidator.validateSet(draft));
    final points = draft.initialWaypoints.isEmpty ? [anchor] : draft.initialWaypoints;
    return _save(
      SetObject(waypoints: [for (final l in points) WaypointObject(location: l)]),
      _base(draft.name, draft.comment, draft.description, draft.colorValue, draft.iconId),
      draft.targetFolder,
    );
  }

  Future<String> createRoute(RouteDraft draft, LandmarkLocation anchor) async {
    _check(CompositeValidator.validateRoute(draft));
    final points = draft.initialWaypoints.isEmpty ? [anchor] : draft.initialWaypoints;
    return _save(
      RouteObject(waypoints: [for (final l in points) WaypointObject(location: l)]),
      _base(draft.name, draft.comment, draft.description, draft.colorValue, draft.iconId),
      draft.targetFolder,
    );
  }

  Future<String> createTrack(TrackDraft draft, LandmarkLocation anchor) async {
    _check(CompositeValidator.validateTrack(draft));
    final locations = draft.initialLocations;
    final segments = locations.isEmpty
        ? const <TrackSegment>[]
        : draft.autoSplitByTime
        ? [for (final part in splitByTime(locations, draft.splitGapSeconds)) TrackSegment(locations: part)]
        : [TrackSegment(locations: locations)];
    return _save(
      TrackObject(waypoints: draft.initialWaypoints, segments: segments),
      {
        ..._base(draft.name, draft.comment, draft.description, draft.colorValue, draft.iconId),
        if (draft.activity?.trim().isNotEmpty ?? false) LandmarkMetadata.activityKey: draft.activity!.trim(),
      },
      draft.targetFolder,
    );
  }

  Future<String> createArea(AreaDraft draft, LandmarkLocation anchor) async {
    _check(CompositeValidator.validateArea(draft));
    final outline = draft.initialOutline.isEmpty ? [anchor] : draft.initialOutline;
    return _save(
      AreaObject(polygons: [AreaPolygon(outline: outline)]),
      {
        ..._base(draft.name, draft.comment, draft.description, draft.colorValue, draft.iconId),
        LandmarkMetadata.closedKey: draft.isClosed,
      },
      draft.targetFolder,
    );
  }

  /// Делит точки на куски там, где пауза между соседними точками со
  /// временем больше [gapSeconds]. Точки без времени разрывов не дают.
  static List<List<LandmarkLocation>> splitByTime(List<LandmarkLocation> locations, int gapSeconds) {
    final parts = <List<LandmarkLocation>>[];
    var current = <LandmarkLocation>[];
    int? previousTime;
    for (final location in locations) {
      final t = CompositeCalculator.timeOf(location);
      if (t != null && previousTime != null && t - previousTime > gapSeconds * 1000 && current.isNotEmpty) {
        parts.add(current);
        current = [];
      }
      current.add(location);
      if (t != null) previousTime = t;
    }
    if (current.isNotEmpty) parts.add(current);
    return parts;
  }

  /// Сохраняет объект, нарисованный в режиме правки ([EditModeController.startNew]),
  /// новым файлом в [targetFolder] (по умолчанию — папка новых меток);
  /// пустые сегменты и контуры отбрасываются.
  Future<String> createObject(LandmarkObject object, {String? targetFolder}) {
    final cleaned = switch (object) {
      TrackObject o => TrackObject(
        waypoints: o.waypoints,
        segments: [for (final s in o.segments) if (s.locations.isNotEmpty) s],
        userMetadata: o.userMetadata,
      ),
      AreaObject o => AreaObject(
        polygons: [for (final p in o.polygons) if (p.outline.isNotEmpty) p],
        userMetadata: o.userMetadata,
      ),
      _ => object,
    };
    return _save(cleaned, {...cleaned.userMetadata.entries.cast<String, Object>()}, targetFolder);
  }

  static Map<String, Object> _base(String? name, String? comment, String? description, int? color, String? icon) => {
    if (name?.trim().isNotEmpty ?? false) LandmarkMetadata.nameKey: name!.trim(),
    if (comment?.trim().isNotEmpty ?? false) LandmarkMetadata.commentKey: comment!,
    if (description?.trim().isNotEmpty ?? false) LandmarkMetadata.descriptionKey: description!,
    LandmarkMetadata.colorKey: ?color,
    if (icon?.isNotEmpty ?? false) LandmarkMetadata.iconKey: icon!,
  };

  Future<String> _save(LandmarkObject object, Map<String, Object> entries, String? targetFolder) async {
    _check(CompositeValidator.validateObject(object));
    final now = _clock().millisecondsSinceEpoch;
    // Статистика зависит от метаданных (у области — от `closed`).
    final stats = _calculator.metadataFor(object.withUserMetadata(LandmarkMetadata(entries: entries)));
    final user = _editor.validateAndBuild({
      ...entries,
      for (final MapEntry(:key, :value) in stats.set.entries) key: value!,
      LandmarkMetadata.createdAtKey: now,
      LandmarkMetadata.updatedAtKey: now,
    });
    final directory = targetFolder ?? await _folders.getDefaultFolder();
    return _repository.save(LandmarkFile.of(object.withUserMetadata(user)), directory: directory);
  }

  static void _check(ValidationResult result) {
    if (!result.isValid) throw ValidationException(result.errors);
  }
}
