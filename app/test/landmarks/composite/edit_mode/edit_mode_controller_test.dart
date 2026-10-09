import 'dart:io';

import 'package:app/landmarks/composite/drafts/area_draft.dart';
import 'package:app/landmarks/composite/drafts/route_draft.dart';
import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/landmarks/composite/edit_mode/edit_commands.dart';
import 'package:app/landmarks/composite/edit_mode/edit_mode_controller.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../services/fixture.dart';
import '../helpers.dart';

void main() {
  late ServicesFixture f;
  late EditModeController edit;
  late String route;
  setUp(() async {
    f = await ServicesFixture.create();
    edit = f.services.editMode;
    route = await f.services.compositeCreation.createRoute(
      RouteDraft(name: 'R', initialWaypoints: [loc(0, 0), loc(1, 1)]),
      loc(0, 0),
    );
  });
  tearDown(() => f.dispose());

  RouteObject current() => edit.state.target!.object as RouteObject;

  test('open: active, not dirty, nothing to undo', () async {
    await edit.open(route, LandmarkType.route);
    expect(edit.state.isActive, isTrue);
    expect(edit.state.isDirty, isFalse);
    expect(edit.canUndo, isFalse);
    expect(edit.state.target!.historyDepth, 0);
  });

  test('execute(AddWaypointCommand) makes it dirty', () async {
    await edit.open(route, LandmarkType.route);
    expect(edit.execute(AddWaypointCommand(waypoint: wp(2, 2))), isTrue);
    expect(edit.state.isDirty, isTrue);
    expect(current().waypoints, hasLength(3));
    expect(edit.state.target!.historyDepth, 1);
  });

  test('undo goes back until nothing is left; redo goes forward', () async {
    await edit.open(route, LandmarkType.route);
    edit.execute(AddWaypointCommand(waypoint: wp(2, 2)));
    edit.execute(const RemoveWaypointCommand(index: 0));
    edit.undo();
    expect(current().waypoints, hasLength(3));
    edit.undo();
    expect(current().waypoints, hasLength(2));
    expect(edit.canUndo, isFalse);
    expect(edit.state.isDirty, isFalse);
    edit.undo();
    expect(edit.canRedo, isTrue);
    edit.redo();
    edit.redo();
    expect(current().waypoints.first.location, loc(1, 1));
    expect(edit.canRedo, isFalse);
  });

  test('a new command clears redo', () async {
    await edit.open(route, LandmarkType.route);
    edit.execute(AddWaypointCommand(waypoint: wp(2, 2)));
    edit.undo();
    edit.execute(const ReorderWaypointsCommand(fromIndex: 0, toIndex: 1));
    expect(edit.canRedo, isFalse);
  });

  test('history keeps the last 50 steps', () async {
    await edit.open(route, LandmarkType.route);
    for (var i = 0; i < 60; i++) {
      edit.execute(UpdateWaypointCommand(index: 0, waypoint: wp(i.toDouble(), 0)));
    }
    expect(edit.state.target!.historyDepth, EditModeController.maxHistory);
    for (var i = 0; i < 60; i++) {
      edit.undo();
    }
    expect(current().waypoints.first.location.latitude, 9);
  });

  test('saveAndClose writes the file once and deactivates', () async {
    await edit.open(route, LandmarkType.route);
    edit.execute(AddWaypointCommand(waypoint: wp(2, 2), atIndex: 1));
    edit.execute(const UpdateMetadataCommand(patch: MetadataPatch(set: {'name': 'Edited'})));
    await edit.saveAndClose();
    expect(edit.state.isActive, isFalse);
    final saved = await f.services.routeService.load(route);
    expect(saved.waypoints, hasLength(3));
    expect(saved.waypoints[1].location, loc(2, 2));
    expect(saved.userMetadata.name, 'Edited');
    expect(saved.userMetadata.version, 1);
  });

  test('close does not write the file', () async {
    final before = File(route).readAsBytesSync();
    await edit.open(route, LandmarkType.route);
    edit.execute(AddWaypointCommand(waypoint: wp(2, 2)));
    edit.close();
    expect(edit.state.isActive, isFalse);
    expect(File(route).readAsBytesSync(), before);
  });

  test('commands that do not fit leave the object and add a warning', () async {
    await edit.open(route, LandmarkType.route);
    expect(edit.execute(const DeleteTrackSegmentCommand(segmentIndex: 0)), isFalse);
    expect(edit.execute(const RemoveWaypointCommand(index: 7)), isFalse);
    expect(edit.execute(UpdateWaypointCommand(index: 0, waypoint: wp(95, 0))), isFalse);
    expect(edit.state.warnings, hasLength(3));
    expect(edit.state.isDirty, isFalse);
    expect(edit.canUndo, isFalse);
  });

  test('track and area commands', () async {
    final track = await f.services.compositeCreation.createTrack(
      TrackDraft(initialLocations: [loc(0, 0), loc(0, 1), loc(0, 2)]),
      loc(0, 0),
    );
    await edit.open(track, LandmarkType.track);
    edit.execute(AddTrackLocationCommand(segmentIndex: 0, location: loc(0, 3)));
    edit.execute(const SplitTrackSegmentCommand(segmentIndex: 0, locIndex: 2));
    edit.execute(const UpdateSegmentMetadataCommand(segmentIndex: 1, patch: MetadataPatch(set: {'name': 'b'})));
    edit.execute(const MergeTrackSegmentsCommand(firstIndex: 0, secondIndex: 1));
    edit.execute(MoveTrackLocationCommand(segmentIndex: 0, index: 0, newLocation: loc(1, 0)));
    edit.execute(const RemoveTrackLocationCommand(segmentIndex: 0, index: 3));
    expect(edit.state.warnings, isEmpty);
    await edit.saveAndClose();
    final saved = await f.services.trackService.load(track);
    expect(saved.segments.single.locations, [loc(1, 0), loc(0, 1), loc(0, 2)]);

    final area = await f.services.compositeCreation.createArea(
      AreaDraft(initialOutline: [loc(0, 0), loc(0, 0.01), loc(0.01, 0.01)]),
      loc(0, 0),
    );
    await edit.open(area, LandmarkType.area);
    edit.execute(AddAreaOutlinePointCommand(polygonIndex: 0, location: loc(0.01, 0)));
    edit.execute(AddHoleCommand(polygonIndex: 0, outline: [loc(0.002, 0.002), loc(0.002, 0.004), loc(0.004, 0.004)]));
    edit.execute(MoveAreaOutlinePointCommand(polygonIndex: 0, index: 0, newLocation: loc(-0.001, 0)));
    edit.execute(const RemoveAreaOutlinePointCommand(polygonIndex: 0, index: 1));
    edit.execute(const RemoveHoleCommand(polygonIndex: 0, holeIndex: 0));
    edit.execute(const DeleteTrackSegmentCommand(segmentIndex: 0));
    expect(edit.state.warnings, hasLength(1));
    await edit.saveAndClose();
    final savedArea = await f.services.areaService.load(area);
    expect(savedArea.polygons.single.outline, [loc(-0.001, 0), loc(0.01, 0.01), loc(0.01, 0)]);
    expect(savedArea.polygons.single.holes, isEmpty);
  });

  test('a waypoint cannot be opened, nor a file of another type', () async {
    await expectLater(edit.open(route, LandmarkType.waypoint), throwsArgumentError);
    await expectLater(edit.open(route, LandmarkType.track), throwsA(anything));
    expect(edit.state.isActive, isFalse);
  });

  test('saveAndClose without changes does not rewrite the file', () async {
    final before = File(route).readAsBytesSync();
    await edit.open(route, LandmarkType.route);
    await edit.saveAndClose();
    expect(File(route).readAsBytesSync(), before);
  });
}
