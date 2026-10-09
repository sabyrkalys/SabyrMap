import 'package:app/landmarks/composite/drafts/area_draft.dart';
import 'package:app/landmarks/composite/drafts/route_draft.dart';
import 'package:app/landmarks/composite/drafts/set_draft.dart';
import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/landmarks/composite/validation/composite_validation_rules.dart';
import 'package:app/landmarks/composite/validation/composite_validator.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final square = [loc(0, 0), loc(0, 1), loc(1, 1), loc(1, 0)];

  test('valid drafts pass', () {
    expect(CompositeValidator.validateSet(SetDraft(name: 'S', initialWaypoints: square)).isValid, isTrue);
    expect(CompositeValidator.validateRoute(RouteDraft(initialWaypoints: square)).isValid, isTrue);
    expect(CompositeValidator.validateTrack(TrackDraft(initialLocations: square)).isValid, isTrue);
    expect(CompositeValidator.validateArea(AreaDraft(initialOutline: square)).isValid, isTrue);
  });

  test('an empty track is fine', () {
    expect(CompositeValidator.validateTrack(const TrackDraft()).isValid, isTrue);
  });

  test('a set with 10001 points fails, 10000 passes', () {
    final many = List.generate(10001, (i) => loc(0, i * 1e-4));
    expect(CompositeValidator.validateSet(SetDraft(initialWaypoints: many)).isValid, isFalse);
    expect(CompositeValidator.validateSet(SetDraft(initialWaypoints: many.sublist(1))).isValid, isTrue);
  });

  test('a route with 5001 points fails', () {
    final many = List.generate(CompositeValidationRules.maxWaypointsPerRoute + 1, (i) => loc(0, i * 1e-4));
    final result = CompositeValidator.validateRoute(RouteDraft(initialWaypoints: many));
    expect(result.isValid, isFalse);
    expect(result.errors.single, contains('5000'));
  });

  test('a closed area needs 3 points; an open one does not', () {
    final two = [loc(0, 0), loc(0, 1)];
    expect(CompositeValidator.validateArea(AreaDraft(initialOutline: two)).errors.single, contains('at least 3'));
    expect(CompositeValidator.validateArea(AreaDraft(initialOutline: two, isClosed: false)).isValid, isTrue);
  });

  test('coordinates out of range fail', () {
    expect(CompositeValidator.validateSet(SetDraft(initialWaypoints: [loc(91, 0)])).isValid, isFalse);
    expect(CompositeValidator.validateTrack(TrackDraft(initialLocations: [loc(0, 181)])).isValid, isFalse);
    expect(CompositeValidator.validateArea(AreaDraft(initialOutline: [...square, loc(double.nan, 0)])).isValid, isFalse);
  });

  test('a long name and a bad colour fail', () {
    expect(CompositeValidator.validateRoute(RouteDraft(name: 'a' * 201)).errors.single, contains('name'));
    expect(CompositeValidator.validateSet(const SetDraft(colorValue: -1)).errors.single, contains('colorValue'));
  });

  test('objects are checked against the limits', () {
    final track = TrackObject(segments: List.generate(1001, (_) => TrackSegment(locations: [loc(0, 0)])));
    expect(CompositeValidator.validateObject(track).errors.single, contains('segments'));
    final area = AreaObject(polygons: [AreaPolygon(outline: [loc(0, 0)], holes: [[loc(95, 0)]])]);
    expect(CompositeValidator.validateObject(area).errors.single, contains('hole'));
    expect(CompositeValidator.validateObject(SetObject(waypoints: [wp(0, 0)])).isValid, isTrue);
  });
}
