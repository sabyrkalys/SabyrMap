import 'package:app/landmarks/composite/operations/segment_ops.dart';
import 'package:app/landmarks/models/landmark_metadata.dart';
import 'package:app/landmarks/models/landmark_track.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  const meta = LandmarkMetadata(entries: {'name': 'first'});
  final s0 = TrackSegment(userMetadata: meta, locations: [loc(0, 0), loc(0, 1), loc(0, 2)]);
  final s1 = TrackSegment(locations: [loc(1, 0), loc(1, 1)]);
  List<int> sizes(List<TrackSegment> s) => [for (final x in s) x.locations.length];

  test('addLocation at the end, at 0, and into an empty track', () {
    expect(SegmentOps.addLocation([s0], 0, loc(9, 9)).single.locations.last, loc(9, 9));
    expect(SegmentOps.addLocation([s0], 0, loc(9, 9), atIndex: 0).single.locations.first, loc(9, 9));
    expect(SegmentOps.addLocation([], 0, loc(9, 9)).single.locations, [loc(9, 9)]);
    expect(() => SegmentOps.addLocation([], 1, loc(9, 9)), throwsRangeError);
    expect(() => SegmentOps.addLocation([s0], 0, loc(9, 9), atIndex: 4), throwsRangeError);
  });

  test('removeLocation and moveLocation', () {
    expect(SegmentOps.removeLocation([s0], 0, 2).single.locations, [loc(0, 0), loc(0, 1)]);
    expect(SegmentOps.moveLocation([s0], 0, 0, loc(5, 5)).single.locations.first, loc(5, 5));
    expect(() => SegmentOps.removeLocation([s0], 0, 3), throwsRangeError);
    expect(() => SegmentOps.moveLocation([s0], 1, 0, loc(5, 5)), throwsRangeError);
  });

  test('splitSegment: the point becomes the first of the second segment', () {
    final split = SegmentOps.splitSegment([s0, s1], 0, 1);
    expect(sizes(split), [1, 2, 2]);
    expect(split[1].locations.first, loc(0, 1));
    expect(split[1].userMetadata, meta);
    expect(SegmentOps.splitSegment([s0], 0, 2).last.locations, [loc(0, 2)]);
  });

  test('splitSegment at 0 or past the end is an error', () {
    expect(() => SegmentOps.splitSegment([s0], 0, 0), throwsArgumentError);
    expect(() => SegmentOps.splitSegment([s0], 0, 3), throwsArgumentError);
  });

  test('deleteSegment', () {
    expect(sizes(SegmentOps.deleteSegment([s0, s1], 1)), [3]);
    expect(SegmentOps.deleteSegment([s0], 0), isEmpty);
    expect(() => SegmentOps.deleteSegment([], 0), throwsRangeError);
  });

  test('mergeSegments appends second to first and drops second', () {
    final merged = SegmentOps.mergeSegments([s0, s1], 0, 1);
    expect(sizes(merged), [5]);
    expect(merged.single.locations.last, loc(1, 1));
    expect(merged.single.userMetadata, meta);
    final reversed = SegmentOps.mergeSegments([s0, s1], 1, 0);
    expect(reversed.single.locations.first, loc(1, 0));
    expect(() => SegmentOps.mergeSegments([s0, s1], 1, 1), throwsArgumentError);
  });

  test('groupAll: one segment, metadata of the first', () {
    final grouped = SegmentOps.groupAll([s0, s1]);
    expect(sizes(grouped), [5]);
    expect(grouped.single.userMetadata, meta);
    expect(SegmentOps.groupAll([]), isEmpty);
  });
}
