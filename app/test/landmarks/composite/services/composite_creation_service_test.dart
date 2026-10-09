import 'dart:io';

import 'package:app/landmarks/composite/drafts/area_draft.dart';
import 'package:app/landmarks/composite/drafts/route_draft.dart';
import 'package:app/landmarks/composite/drafts/set_draft.dart';
import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/landmarks/composite/services/composite_creation_service.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../services/fixture.dart';
import '../helpers.dart';

void main() {
  late ServicesFixture f;
  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.dispose());
  final anchor = loc(50, 30);

  test('a valid set is saved into the default folder, version 0', () async {
    final path = await f.services.compositeCreation.createSet(
      SetDraft(name: 'Posts', colorValue: 0xFF00FF00, initialWaypoints: [loc(50, 30), loc(50.1, 30.1)]),
      anchor,
    );
    expect(p.dirname(path), f.paths.importDefault);
    expect(p.extension(path), '.set');
    final set = await f.services.setService.load(path);
    expect(set.waypoints, hasLength(2));
    expect(set.userMetadata.version, 0);
    expect(set.userMetadata.name, 'Posts');
    expect(set.userMetadata.colorValue, 0xFF00FF00);
    expect(set.userMetadata.createdAtMs, 1760000000000);
    expect(set.userMetadata.updatedAtMs, 1760000000000);
    expect(set.userMetadata.entries['length_m'], greaterThan(0));
  });

  test('an empty set or route starts at the anchor; targetFolder is used', () async {
    final dir = p.join(f.paths.landmarks, 'trip');
    final path = await f.services.compositeCreation.createRoute(RouteDraft(targetFolder: dir), anchor);
    expect(p.dirname(path), dir);
    expect((await f.services.routeService.load(path)).waypoints.single.location, anchor);
  });

  test('an invalid draft throws and writes nothing', () async {
    await expectLater(
      f.services.compositeCreation.createSet(SetDraft(initialWaypoints: [loc(95, 0)]), anchor),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      f.services.compositeCreation.createArea(AreaDraft(initialOutline: [loc(0, 0)]), anchor),
      throwsA(isA<ValidationException>()),
    );
    expect(Directory(f.paths.landmarks).listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('autoSplitByTime splits on pauses longer than the gap', () async {
    final locations = [
      loc(0, 0, t: 0),
      loc(0, 0.001, t: 10000),
      loc(0, 0.002, t: 400000),
      loc(0, 0.003),
      loc(0, 0.004, t: 410000),
      loc(0, 0.005, t: 2000000),
    ];
    final path = await f.services.compositeCreation.createTrack(
      TrackDraft(name: 'Walk', initialLocations: locations, autoSplitByTime: true, splitGapSeconds: 300, activity: 'hike'),
      anchor,
    );
    final track = await f.services.trackService.load(path);
    expect([for (final s in track.segments) s.locations.length], [2, 3, 1]);
    expect(track.userMetadata.entries['activity'], 'hike');
    expect(track.userMetadata.entries['duration_ms'], 2000000);
  });

  test('without autoSplit or without times there is one segment; an empty track stays empty', () async {
    final noTimes = [loc(0, 0), loc(0, 1), loc(0, 2)];
    final one = await f.services.compositeCreation.createTrack(
      TrackDraft(initialLocations: noTimes, autoSplitByTime: true),
      anchor,
    );
    expect((await f.services.trackService.load(one)).segments.single.locations, hasLength(3));
    final empty = await f.services.compositeCreation.createTrack(const TrackDraft(), anchor);
    expect((await f.services.trackService.load(empty)).segments, isEmpty);
  });

  test('an open area keeps its outline open', () async {
    final outline = [loc(0, 0), loc(0, 0.01), loc(0.01, 0.01)];
    final path = await f.services.compositeCreation.createArea(AreaDraft(initialOutline: outline, isClosed: false), anchor);
    final area = await f.services.areaService.load(path);
    expect(area.polygons.single.outline, outline);
    expect(area.userMetadata.entries['closed'], isFalse);
    expect(f.services.calculator.forArea(area).areaSquareMeters, 0);
    expect(area.userMetadata.entries['area_m2'], 0.0);
  });

  test('splitByTime directly', () {
    expect(CompositeCreationService.splitByTime(const [], 60), isEmpty);
    expect(CompositeCreationService.splitByTime([loc(0, 0, t: 0), loc(0, 0, t: 61000)], 60), hasLength(2));
    expect(CompositeCreationService.splitByTime([loc(0, 0, t: 0), loc(0, 0, t: 60000)], 60), hasLength(1));
  });

  test('the explorer reads the new files', () async {
    final path = await f.services.compositeCreation.createSet(SetDraft(name: 'S', initialWaypoints: [loc(0, 0)]), anchor);
    final file = await f.services.repository.load(path);
    expect(file.type, LandmarkType.set);
  });
}
