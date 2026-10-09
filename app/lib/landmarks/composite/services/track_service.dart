import 'package:app/landmarks/composite/operations/segment_ops.dart';
import 'package:app/landmarks/composite/operations/waypoint_ops.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';

import 'composite_service.dart';

/// Правка трека: путевые точки, точки сегментов, сами сегменты.
/// Каждая операция — отдельная запись файла.
class TrackService extends CompositeService<TrackObject> {
  TrackService(super.repository, {super.editor, super.calculator});

  @override
  LandmarkType get type => LandmarkType.track;

  Future<TrackObject> addWaypoint(String path, WaypointObject wp) =>
      mutate(path, (o) => withWaypoints(o, WaypointOps.add(o.waypoints, wp)));

  Future<TrackObject> removeWaypoint(String path, int index) =>
      mutate(path, (o) => withWaypoints(o, WaypointOps.removeAt(o.waypoints, index)));

  Future<TrackObject> updateWaypointAt(String path, int index, WaypointObject wp) =>
      mutate(path, (o) => withWaypoints(o, WaypointOps.replaceAt(o.waypoints, index, wp)));

  /// Точка в конец сегмента [segIndex]; в пустом треке индекс 0 создаёт сегмент.
  Future<TrackObject> addLocation(String path, int segIndex, LandmarkLocation loc) =>
      mutate(path, (o) => withSegments(o, SegmentOps.addLocation(o.segments, segIndex, loc)));

  Future<TrackObject> insertLocation(String path, int segIndex, int locIndex, LandmarkLocation loc) =>
      mutate(path, (o) => withSegments(o, SegmentOps.addLocation(o.segments, segIndex, loc, atIndex: locIndex)));

  Future<TrackObject> removeLocation(String path, int segIndex, int locIndex) =>
      mutate(path, (o) => withSegments(o, SegmentOps.removeLocation(o.segments, segIndex, locIndex)));

  Future<TrackObject> moveLocation(String path, int segIndex, int locIndex, LandmarkLocation newLoc) =>
      mutate(path, (o) => withSegments(o, SegmentOps.moveLocation(o.segments, segIndex, locIndex, newLoc)));

  /// Точка [locIndex] становится первой во втором сегменте.
  Future<TrackObject> splitSegmentAt(String path, int segIndex, int locIndex) =>
      mutate(path, (o) => withSegments(o, SegmentOps.splitSegment(o.segments, segIndex, locIndex)));

  Future<TrackObject> deleteSegment(String path, int segIndex) =>
      mutate(path, (o) => withSegments(o, SegmentOps.deleteSegment(o.segments, segIndex)));

  /// Все точки в одном сегменте с метаданными первого.
  Future<TrackObject> groupAllSegments(String path) => mutate(path, (o) => withSegments(o, SegmentOps.groupAll(o.segments)));

  /// [secondIndex] дописывается в конец [firstIndex] и удаляется.
  Future<TrackObject> mergeSegments(String path, int firstIndex, int secondIndex) =>
      mutate(path, (o) => withSegments(o, SegmentOps.mergeSegments(o.segments, firstIndex, secondIndex)));

  /// Метаданные сегмента (без версии и времени — они у трека целиком).
  Future<TrackObject> updateSegmentMetadata(String path, int segIndex, MetadataPatch patch) =>
      mutate(path, (o) => withSegmentMetadata(o, segIndex, patch));

  /// Копия трека с правкой метаданных сегмента [segIndex].
  TrackObject withSegmentMetadata(TrackObject o, int segIndex, MetadataPatch patch) {
    RangeError.checkValidIndex(segIndex, o.segments, 'segIndex');
    final segment = o.segments[segIndex];
    final updated = TrackSegment(userMetadata: editor.merge(segment.userMetadata, patch), locations: segment.locations);
    return withSegments(o, [...o.segments]..[segIndex] = updated);
  }

  static TrackObject withWaypoints(TrackObject o, List<WaypointObject> waypoints) => TrackObject(
    waypoints: waypoints,
    segments: o.segments,
    userMetadata: o.userMetadata,
    technicalMetadata: o.technicalMetadata,
  );

  static TrackObject withSegments(TrackObject o, List<TrackSegment> segments) => TrackObject(
    waypoints: o.waypoints,
    segments: segments,
    userMetadata: o.userMetadata,
    technicalMetadata: o.technicalMetadata,
  );
}
