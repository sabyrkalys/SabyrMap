import 'package:collection/collection.dart';

import 'landmark_metadata.dart';
import 'landmark_object.dart';
import 'landmark_type.dart';
import 'landmark_waypoint.dart';

/// Набор путевых точек без порядка обхода (файл `.set`).
class SetObject extends LandmarkObject {
  const SetObject({
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
  LandmarkType get type => LandmarkType.set;

  @override
  SetObject withUserMetadata(LandmarkMetadata userMetadata) =>
      SetObject(waypoints: waypoints, userMetadata: userMetadata, technicalMetadata: technicalMetadata);

  @override
  SetObject withTechnicalMetadata(LandmarkMetadata technicalMetadata) =>
      SetObject(waypoints: waypoints, userMetadata: userMetadata, technicalMetadata: technicalMetadata);

  static const _equality = ListEquality<WaypointObject>();

  @override
  bool operator ==(Object other) =>
      other is SetObject &&
      _equality.equals(other.waypoints, waypoints) &&
      other.userMetadata == userMetadata &&
      other.technicalMetadata == technicalMetadata;

  @override
  int get hashCode => Object.hash(_equality.hash(waypoints), userMetadata, technicalMetadata);
}
