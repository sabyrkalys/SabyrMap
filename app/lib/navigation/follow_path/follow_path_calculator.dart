import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/landmarks/composite/statistics/elevation_profile.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_track.dart';

import 'follow_path_dashboard.dart';

/// Расчёты следования по треку. Переходы между сегментами длины не
/// добавляют (это разрывы записи).
abstract final class FollowPathCalculator {
  static FollowPathDashboard computeDashboard({
    required TrackObject track,
    required LandmarkLocation position,
    required int currentSegmentIndex,
    required int currentPointIndex,
    double? currentSpeedMps,
  }) {
    var remaining = 0.0;
    var gain = 0.0;
    var loss = 0.0;
    for (var s = currentSegmentIndex; s < track.segments.length; s++) {
      final locations = track.segments[s].locations;
      final rest = s == currentSegmentIndex ? locations.sublist(currentPointIndex.clamp(0, locations.length)) : locations;
      remaining += Haversine.totalDistance(rest);
      final profile = ElevationProfileBuilder.build(rest);
      gain += profile.gain;
      loss += profile.loss;
    }
    return FollowPathDashboard(
      remainingDistanceMeters: remaining,
      remainingGainMeters: gain,
      remainingLossMeters: loss,
      etaSeconds: currentSpeedMps != null && currentSpeedMps > 0 ? (remaining / currentSpeedMps).round() : null,
      distanceToTrackMeters: distanceToTrack(track: track, position: position),
      currentSegmentIndex: currentSegmentIndex,
    );
  }

  /// Ближайшая точка трека перебором всех точек. Трек без точек —
  /// [ArgumentError].
  static (int segmentIndex, int pointIndex, double distanceMeters) findClosestPoint({
    required TrackObject track,
    required LandmarkLocation position,
  }) {
    (int, int, double)? best;
    for (final (s, segment) in track.segments.indexed) {
      for (final (i, location) in segment.locations.indexed) {
        final d = Haversine.distance(position, location);
        if (best == null || d < best.$3) best = (s, i, d);
      }
    }
    if (best == null) throw ArgumentError('track has no points');
    return best;
  }

  /// Наименьшее расстояние до точки трека.
  static double distanceToTrack({required TrackObject track, required LandmarkLocation position}) =>
      findClosestPoint(track: track, position: position).$3;

  /// Точка впереди: от текущей вперёд копится длина, пока не наберётся
  /// [distanceMeters]; 0 — текущая точка; дальше конца трека — null.
  static LandmarkLocation? autoTargetAhead({
    required TrackObject track,
    required int segmentIndex,
    required int pointIndex,
    required double distanceMeters,
  }) {
    if (segmentIndex >= track.segments.length) return null;
    var accumulated = 0.0;
    for (var s = segmentIndex; s < track.segments.length; s++) {
      final locations = track.segments[s].locations;
      // Разрыв между сегментами длины не добавляет.
      LandmarkLocation? previous;
      for (var i = s == segmentIndex ? pointIndex : 0; i < locations.length; i++) {
        final location = locations[i];
        if (previous != null) accumulated += Haversine.distance(previous, location);
        if (accumulated >= distanceMeters) return location;
        previous = location;
      }
    }
    return null;
  }
}
