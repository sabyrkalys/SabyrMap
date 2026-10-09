import 'package:collection/collection.dart';

import 'landmark_location.dart';
import 'landmark_metadata.dart';
import 'landmark_object.dart';
import 'landmark_type.dart';
import 'landmark_waypoint.dart';

/// Трек: записанный путь из сегментов и привязанные к нему точки (файл `.trk`).
class TrackObject extends LandmarkObject {
  const TrackObject({
    this.waypoints = const [],
    this.segments = const [],
    this.userMetadata = const LandmarkMetadata(),
    this.technicalMetadata = const LandmarkMetadata(),
  });

  final List<WaypointObject> waypoints;
  final List<TrackSegment> segments;

  @override
  final LandmarkMetadata userMetadata;

  @override
  final LandmarkMetadata technicalMetadata;

  @override
  LandmarkType get type => LandmarkType.track;

  @override
  TrackObject withUserMetadata(LandmarkMetadata userMetadata) =>
      TrackObject(
    waypoints: waypoints,
    segments: segments,
    userMetadata: userMetadata,
    technicalMetadata: technicalMetadata,
  );

  @override
  TrackObject withTechnicalMetadata(LandmarkMetadata technicalMetadata) => TrackObject(
    waypoints: waypoints,
    segments: segments,
    userMetadata: userMetadata,
    technicalMetadata: technicalMetadata,
  );

  static const _waypoints = ListEquality<WaypointObject>();
  static const _segments = ListEquality<TrackSegment>();

  @override
  bool operator ==(Object other) =>
      other is TrackObject &&
      _waypoints.equals(other.waypoints, waypoints) &&
      _segments.equals(other.segments, segments) &&
      other.userMetadata == userMetadata &&
      other.technicalMetadata == technicalMetadata;

  @override
  int get hashCode => Object.hash(_waypoints.hash(waypoints), _segments.hash(segments), userMetadata, technicalMetadata);
}

/// Непрерывный кусок трека (между паузами записи).
class TrackSegment {
  const TrackSegment({this.userMetadata = const LandmarkMetadata(), this.locations = const []});

  final LandmarkMetadata userMetadata;
  final List<LandmarkLocation> locations;

  static const _equality = ListEquality<LandmarkLocation>();

  @override
  bool operator ==(Object other) =>
      other is TrackSegment && other.userMetadata == userMetadata && _equality.equals(other.locations, locations);

  @override
  int get hashCode => Object.hash(userMetadata, _equality.hash(locations));
}
