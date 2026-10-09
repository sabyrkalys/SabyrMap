import 'package:app/landmarks/composite/operations/polygon_ops.dart';
import 'package:app/landmarks/composite/operations/segment_ops.dart';
import 'package:app/landmarks/composite/operations/waypoint_ops.dart';
import 'package:app/landmarks/composite/services/area_service.dart';
import 'package:app/landmarks/composite/services/composite_service.dart';
import 'package:app/landmarks/composite/services/route_service.dart';
import 'package:app/landmarks/composite/services/set_service.dart';
import 'package:app/landmarks/composite/services/track_service.dart';
import 'package:app/landmarks/composite/validation/composite_validator.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:flutter/foundation.dart';

import 'edit_commands.dart';
import 'edit_mode_state.dart';
import 'edit_mode_target.dart';

/// Режим правки набора, маршрута, трека или области: команды меняют копию
/// объекта в памяти, есть отмена и повтор, файл пишется только в
/// [saveAndClose].
class EditModeController extends ChangeNotifier {
  EditModeController({
    required SetService setService,
    required RouteService routeService,
    required TrackService trackService,
    required AreaService areaService,
  }) : _set = setService,
       _route = routeService,
       _track = trackService,
       _area = areaService;

  final SetService _set;
  final RouteService _route;
  final TrackService _track;
  final AreaService _area;

  /// Сколько шагов отмены хранится.
  static const int maxHistory = 50;

  EditModeState _state = const EditModeState();
  LandmarkObject? _original;
  final List<LandmarkObject> _undo = [];
  final List<LandmarkObject> _redo = [];

  EditModeState get state => _state;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Открывает файл [path] типа [type]. Путевая точка — [ArgumentError];
  /// файл другого типа — ошибка сервиса.
  Future<void> open(String path, LandmarkType type) async {
    final object = await _serviceFor(type).load(path);
    _original = object;
    _undo.clear();
    _redo.clear();
    _state = EditModeState(target: EditModeTarget(filePath: path, type: type, object: object));
    notifyListeners();
  }

  /// Закрывает без записи.
  void close() {
    _original = null;
    _undo.clear();
    _redo.clear();
    _state = const EditModeState();
    notifyListeners();
  }

  /// Записывает правки (если они есть) через сервис типа и закрывает.
  /// Ошибка записи оставляет режим открытым.
  Future<void> saveAndClose() async {
    final target = _state.target;
    if (target == null) return;
    if (target.isDirty) await _write(target);
    close();
  }

  /// Применяет команду. Неприменимая команда (не тот тип, неверный
  /// индекс, превышен предел) ничего не меняет, а её причина попадает в
  /// [EditModeState.warnings]. Возвращает, применилась ли команда.
  bool execute(EditCommand command) {
    final target = _state.target;
    if (target == null) return false;
    final LandmarkObject next;
    try {
      next = _apply(target.object, command);
      final result = CompositeValidator.validateObject(next);
      if (!result.isValid) throw ValidationException(result.errors);
    } on Object catch (e) {
      if (e is! ArgumentError && e is! ValidationException && e is! StateError) rethrow;
      _state = EditModeState(target: target, warnings: [..._state.warnings, _describe(e)]);
      notifyListeners();
      return false;
    }
    _undo.add(target.object);
    if (_undo.length > maxHistory) _undo.removeAt(0);
    _redo.clear();
    _show(next);
    return true;
  }

  void undo() {
    final target = _state.target;
    if (target == null || _undo.isEmpty) return;
    _redo.add(target.object);
    _show(_undo.removeLast());
  }

  void redo() {
    final target = _state.target;
    if (target == null || _redo.isEmpty) return;
    _undo.add(target.object);
    _show(_redo.removeLast());
  }

  void _show(LandmarkObject object) {
    final target = _state.target!;
    _state = EditModeState(
      target: target.copyWith(object: object, isDirty: object != _original, historyDepth: _undo.length),
    );
    notifyListeners();
  }

  CompositeService _serviceFor(LandmarkType type) => switch (type) {
    LandmarkType.set => _set,
    LandmarkType.route => _route,
    LandmarkType.track => _track,
    LandmarkType.area => _area,
    LandmarkType.waypoint => throw ArgumentError.value(type, 'type', 'edit mode is for sets, routes, tracks and areas'),
  };

  Future<void> _write(EditModeTarget target) => switch (target.object) {
    final SetObject o => _set.save(target.filePath, o),
    final RouteObject o => _route.save(target.filePath, o),
    final TrackObject o => _track.save(target.filePath, o),
    final AreaObject o => _area.save(target.filePath, o),
    _ => throw StateError('Unsupported object ${target.object.runtimeType}'),
  };

  LandmarkObject _apply(LandmarkObject o, EditCommand command) => switch (command) {
    AddWaypointCommand(:final waypoint, :final atIndex) =>
      _withWaypoints(o, WaypointOps.add(_waypoints(o), waypoint, atIndex: atIndex)),
    RemoveWaypointCommand(:final index) => _withWaypoints(o, WaypointOps.removeAt(_waypoints(o), index)),
    UpdateWaypointCommand(:final index, :final waypoint) =>
      _withWaypoints(o, WaypointOps.replaceAt(_waypoints(o), index, waypoint)),
    ReorderWaypointsCommand(:final fromIndex, :final toIndex) =>
      _withWaypoints(o, WaypointOps.reorder(_waypoints(o), fromIndex, toIndex)),
    AddTrackLocationCommand(:final segmentIndex, :final atIndex, :final location) => _changeTrack(
      o,
      (t) => SegmentOps.addLocation(t.segments, segmentIndex, location, atIndex: atIndex),
    ),
    RemoveTrackLocationCommand(:final segmentIndex, :final index) =>
      _changeTrack(o, (t) => SegmentOps.removeLocation(t.segments, segmentIndex, index)),
    MoveTrackLocationCommand(:final segmentIndex, :final index, :final newLocation) =>
      _changeTrack(o, (t) => SegmentOps.moveLocation(t.segments, segmentIndex, index, newLocation)),
    SplitTrackSegmentCommand(:final segmentIndex, :final locIndex) =>
      _changeTrack(o, (t) => SegmentOps.splitSegment(t.segments, segmentIndex, locIndex)),
    DeleteTrackSegmentCommand(:final segmentIndex) =>
      _changeTrack(o, (t) => SegmentOps.deleteSegment(t.segments, segmentIndex)),
    MergeTrackSegmentsCommand(:final firstIndex, :final secondIndex) =>
      _changeTrack(o, (t) => SegmentOps.mergeSegments(t.segments, firstIndex, secondIndex)),
    AddAreaOutlinePointCommand(:final polygonIndex, :final atIndex, :final location) =>
      _changePolygon(o, polygonIndex, (p) => PolygonOps.addOutlinePoint(p, location, atIndex: atIndex)),
    RemoveAreaOutlinePointCommand(:final polygonIndex, :final index) =>
      _changePolygon(o, polygonIndex, (p) => PolygonOps.removeOutlinePoint(p, index)),
    MoveAreaOutlinePointCommand(:final polygonIndex, :final index, :final newLocation) =>
      _changePolygon(o, polygonIndex, (p) => PolygonOps.moveOutlinePoint(p, index, newLocation)),
    AddHoleCommand(:final polygonIndex, :final outline) =>
      _changePolygon(o, polygonIndex, (p) => PolygonOps.addHole(p, outline)),
    RemoveHoleCommand(:final polygonIndex, :final holeIndex) =>
      _changePolygon(o, polygonIndex, (p) => PolygonOps.removeHole(p, holeIndex)),
    UpdateMetadataCommand(:final patch) => o.withUserMetadata(_set.editor.merge(o.userMetadata, patch)),
    UpdateSegmentMetadataCommand(:final segmentIndex, :final patch) =>
      _track.withSegmentMetadata(_asTrack(o), segmentIndex, patch),
  };

  static List<WaypointObject> _waypoints(LandmarkObject o) => switch (o) {
    SetObject(:final waypoints) || RouteObject(:final waypoints) || TrackObject(:final waypoints) => waypoints,
    _ => throw ArgumentError('${o.type.extension} has no waypoint list'),
  };

  static LandmarkObject _withWaypoints(LandmarkObject o, List<WaypointObject> waypoints) => switch (o) {
    SetObject() => SetObject(waypoints: waypoints, userMetadata: o.userMetadata, technicalMetadata: o.technicalMetadata),
    RouteObject() =>
      RouteObject(waypoints: waypoints, userMetadata: o.userMetadata, technicalMetadata: o.technicalMetadata),
    TrackObject() => TrackService.withWaypoints(o, waypoints),
    _ => throw ArgumentError('${o.type.extension} has no waypoint list'),
  };

  static TrackObject _asTrack(LandmarkObject o) =>
      o is TrackObject ? o : throw ArgumentError('${o.type.extension} is not a track');

  static TrackObject _changeTrack(LandmarkObject o, List<TrackSegment> Function(TrackObject) change) {
    final track = _asTrack(o);
    return TrackService.withSegments(track, change(track));
  }

  static AreaObject _changePolygon(LandmarkObject o, int index, AreaPolygon Function(AreaPolygon) change) {
    if (o is! AreaObject) throw ArgumentError('${o.type.extension} is not an area');
    return AreaService.changePolygon(o, index, change);
  }

  static String _describe(Object e) => switch (e) {
    ArgumentError(:final message) when e is! RangeError => '$message',
    ValidationException(:final errors) => errors.join('; '),
    _ => e.toString(),
  };
}
