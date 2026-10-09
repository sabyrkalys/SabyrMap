import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/landmarks/models/landmark_track.dart';
import 'package:app/navigation/follow_path/follow_path_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  // 0.009° широты ≈ 1 км.
  const step = 0.0044966;
  final straight = TrackObject(
    segments: [
      TrackSegment(locations: [loc(0, 0, ele: 100), loc(step, 0, ele: 130), loc(2 * step, 0, ele: 110)]),
    ],
  );

  test('findClosestPoint on a straight 3-point track', () {
    final (s, p, d) = FollowPathCalculator.findClosestPoint(track: straight, position: loc(step * 1.1, 0.0001));
    expect((s, p), (0, 1));
    expect(d, closeTo(Haversine.distance(loc(step * 1.1, 0.0001), loc(step, 0)), 1e-6));
    expect(
      () => FollowPathCalculator.findClosestPoint(track: const TrackObject(), position: loc(0, 0)),
      throwsArgumentError,
    );
  });

  test('distanceToTrack is the minimum over every point of every segment', () {
    final two = TrackObject(
      segments: [
        TrackSegment(locations: [loc(0, 0)]),
        TrackSegment(locations: [loc(1, 1)]),
      ],
    );
    expect(FollowPathCalculator.distanceToTrack(track: two, position: loc(1, 1.001)), closeTo(111.2, 1));
  });

  test('autoTargetAhead: 0 is the current point; beyond the end is null', () {
    expect(
      FollowPathCalculator.autoTargetAhead(track: straight, segmentIndex: 0, pointIndex: 1, distanceMeters: 0),
      straight.segments.single.locations[1],
    );
    expect(
      FollowPathCalculator.autoTargetAhead(track: straight, segmentIndex: 0, pointIndex: 0, distanceMeters: 300),
      straight.segments.single.locations[1],
    );
    expect(
      FollowPathCalculator.autoTargetAhead(track: straight, segmentIndex: 0, pointIndex: 0, distanceMeters: 5000),
      isNull,
    );
  });

  test('autoTargetAhead crosses segments without counting the gap', () {
    final split = TrackObject(
      segments: [
        TrackSegment(locations: [loc(0, 0), loc(step, 0)]),
        TrackSegment(locations: [loc(5, 5), loc(5 + step, 5)]),
      ],
    );
    expect(
      FollowPathCalculator.autoTargetAhead(track: split, segmentIndex: 0, pointIndex: 0, distanceMeters: 900),
      loc(5 + step, 5),
    );
  });

  test('remaining distance on a straight 1 km track is 1 km; gain and loss', () {
    final d = FollowPathCalculator.computeDashboard(
      track: straight,
      position: loc(0, 0),
      currentSegmentIndex: 0,
      currentPointIndex: 0,
    );
    expect(d.remainingDistanceMeters, closeTo(1000, 1));
    expect(d.remainingGainMeters, closeTo(30, 1e-9));
    expect(d.remainingLossMeters, closeTo(20, 1e-9));
    expect(d.distanceToTrackMeters, 0);
    expect(d.etaSeconds, isNull);
    final later = FollowPathCalculator.computeDashboard(
      track: straight,
      position: loc(step, 0),
      currentSegmentIndex: 0,
      currentPointIndex: 1,
    );
    expect(later.remainingDistanceMeters, closeTo(500, 1));
    expect(later.remainingGainMeters, 0);
  });

  test('ETA with speed', () {
    final d = FollowPathCalculator.computeDashboard(
      track: straight,
      position: loc(0, 0),
      currentSegmentIndex: 0,
      currentPointIndex: 0,
      currentSpeedMps: 2,
    );
    expect(d.etaSeconds, closeTo(500, 1));
  });
}
