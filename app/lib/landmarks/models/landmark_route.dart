import 'package:collection/collection.dart';

import 'landmark_metadata.dart';
import 'landmark_object.dart';
import 'landmark_type.dart';
import 'landmark_waypoint.dart';

/// Маршрут: путевые точки в порядке обхода (файл `.rte`).
class RouteObject extends LandmarkObject {
  const RouteObject({
    this.waypoints = const [],
    this.userMetadata = const LandmarkMetadata(),
    this.technicalMetadata = const LandmarkMetadata(),
  });

  final List<WaypointObject> waypoints;

  @override
  final LandmarkMetadata userMetadata;

  @override
  final LandmarkMetadata technicalMetadata;

  @override
  LandmarkType get type => LandmarkType.route;

  @override
  RouteObject withUserMetadata(LandmarkMetadata userMetadata) =>
      RouteObject(waypoints: waypoints, userMetadata: userMetadata, technicalMetadata: technicalMetadata);

  @override
  RouteObject withTechnicalMetadata(LandmarkMetadata technicalMetadata) =>
      RouteObject(waypoints: waypoints, userMetadata: userMetadata, technicalMetadata: technicalMetadata);

  static const _equality = ListEquality<WaypointObject>();

  @override
  bool operator ==(Object other) =>
      other is RouteObject &&
      _equality.equals(other.waypoints, waypoints) &&
      other.userMetadata == userMetadata &&
      other.technicalMetadata == technicalMetadata;

  @override
  int get hashCode => Object.hash(_equality.hash(waypoints), userMetadata, technicalMetadata);
}
