import 'package:app/landmarks/composite/operations/waypoint_ops.dart';
import 'package:app/landmarks/models/landmark_file.dart';

import 'composite_service.dart';

/// Правка маршрута. Каждая операция — отдельная запись файла.
class RouteService extends CompositeService<RouteObject> {
  RouteService(super.repository, {super.editor, super.calculator});

  @override
  LandmarkType get type => LandmarkType.route;

  Future<RouteObject> addWaypoint(String path, WaypointObject wp) =>
      mutate(path, (o) => _with(o, WaypointOps.add(o.waypoints, wp)));

  /// Вставляет точку на место [index] (0 — в начало, длина — в конец).
  Future<RouteObject> insertWaypointAt(String path, int index, WaypointObject wp) =>
      mutate(path, (o) => _with(o, WaypointOps.add(o.waypoints, wp, atIndex: index)));

  Future<RouteObject> removeWaypoint(String path, int index) =>
      mutate(path, (o) => _with(o, WaypointOps.removeAt(o.waypoints, index)));

  Future<RouteObject> updateWaypointAt(String path, int index, WaypointObject wp) =>
      mutate(path, (o) => _with(o, WaypointOps.replaceAt(o.waypoints, index, wp)));

  Future<RouteObject> reorderWaypoints(String path, int from, int to) =>
      mutate(path, (o) => _with(o, WaypointOps.reorder(o.waypoints, from, to)));

  static RouteObject _with(RouteObject o, List<WaypointObject> waypoints) =>
      RouteObject(waypoints: waypoints, userMetadata: o.userMetadata, technicalMetadata: o.technicalMetadata);
}
