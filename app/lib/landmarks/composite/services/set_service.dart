import 'package:app/landmarks/composite/operations/waypoint_ops.dart';
import 'package:app/landmarks/models/landmark_file.dart';

import 'composite_service.dart';

/// Правка набора точек. Каждая операция — отдельная запись файла.
class SetService extends CompositeService<SetObject> {
  SetService(super.repository, {super.editor, super.calculator});

  @override
  LandmarkType get type => LandmarkType.set;

  Future<SetObject> addWaypoint(String path, WaypointObject wp) =>
      mutate(path, (o) => _with(o, WaypointOps.add(o.waypoints, wp)));

  Future<SetObject> removeWaypoint(String path, int index) =>
      mutate(path, (o) => _with(o, WaypointOps.removeAt(o.waypoints, index)));

  Future<SetObject> updateWaypointAt(String path, int index, WaypointObject wp) =>
      mutate(path, (o) => _with(o, WaypointOps.replaceAt(o.waypoints, index, wp)));

  Future<SetObject> reorderWaypoints(String path, int from, int to) =>
      mutate(path, (o) => _with(o, WaypointOps.reorder(o.waypoints, from, to)));

  static SetObject _with(SetObject o, List<WaypointObject> waypoints) =>
      SetObject(waypoints: waypoints, userMetadata: o.userMetadata, technicalMetadata: o.technicalMetadata);
}
