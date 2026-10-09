import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../services/fixture.dart';
import '../helpers.dart';

void main() {
  late ServicesFixture f;
  late String path;
  setUp(() async {
    f = await ServicesFixture.create();
    path = await f.services.compositeCreation.createTrack(
      TrackDraft(initialLocations: [loc(0, 0), loc(0, 1), loc(0, 2), loc(0, 3)]),
      loc(0, 0),
    );
  });
  tearDown(() => f.dispose());

  List<int> sizes(TrackObject t) => [for (final s in t.segments) s.locations.length];

  test('addLocation: one more point', () async {
    final t = await f.services.trackService.addLocation(path, 0, loc(0, 4));
    expect(sizes(t), [5]);
    expect(t.segments.single.locations.last, loc(0, 4));
    expect(t.userMetadata.version, 1);
  });

  test('insert, move and remove a location', () async {
    await f.services.trackService.insertLocation(path, 0, 1, loc(5, 5));
    await f.services.trackService.moveLocation(path, 0, 0, loc(6, 6));
    final t = await f.services.trackService.removeLocation(path, 0, 4);
    expect(t.segments.single.locations, [loc(6, 6), loc(5, 5), loc(0, 1), loc(0, 2)]);
  });

  test('splitSegmentAt: one more segment, the point starts the second', () async {
    final t = await f.services.trackService.splitSegmentAt(path, 0, 1);
    expect(sizes(t), [1, 3]);
    expect(t.segments[1].locations.first, loc(0, 1));
    await expectLater(f.services.trackService.splitSegmentAt(path, 0, 0), throwsArgumentError);
  });

  test('groupAllSegments: one segment with every point', () async {
    await f.services.trackService.splitSegmentAt(path, 0, 2);
    await f.services.trackService.splitSegmentAt(path, 1, 1);
    final t = await f.services.trackService.groupAllSegments(path);
    expect(sizes(t), [4]);
    expect(t.segments.single.locations, [loc(0, 0), loc(0, 1), loc(0, 2), loc(0, 3)]);
  });

  test('mergeSegments(0, 1): one segment less, points joined', () async {
    await f.services.trackService.splitSegmentAt(path, 0, 3);
    final t = await f.services.trackService.mergeSegments(path, 0, 1);
    expect(sizes(t), [4]);
  });

  test('deleteSegment: one segment less', () async {
    await f.services.trackService.splitSegmentAt(path, 0, 2);
    final t = await f.services.trackService.deleteSegment(path, 0);
    expect(sizes(t), [2]);
    expect(t.segments.single.locations.first, loc(0, 2));
  });

  test('waypoints and segment metadata', () async {
    await f.services.trackService.addWaypoint(path, wp(0, 1, 'stop'));
    await f.services.trackService.updateWaypointAt(path, 0, wp(0, 1, 'rest'));
    var t = await f.services.trackService.updateSegmentMetadata(path, 0, const MetadataPatch(set: {'name': 'day 1'}));
    expect(t.waypoints.single.userMetadata.name, 'rest');
    expect(t.segments.single.userMetadata, const LandmarkMetadata(entries: {'name': 'day 1'}));
    t = await f.services.trackService.removeWaypoint(path, 0);
    expect(t.waypoints, isEmpty);
    expect(t.userMetadata.version, 4);
  });

  test('a point can be added to an empty track', () async {
    final empty = await f.services.compositeCreation.createTrack(const TrackDraft(), loc(0, 0));
    final t = await f.services.trackService.addLocation(empty, 0, loc(1, 1));
    expect(sizes(t), [1]);
  });
}
