import 'dart:convert';

import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/formats/gpx/gpx_parser.dart';
import 'package:app/landmarks/import_export/formats/gpx/gpx_serializer.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  const serializer = GpxSerializer();
  const parser = GpxParser();
  const separate = ImportOptions(extras: {GpxParser.includeWaypointsInTrack: false});

  final waypoint = WaypointObject(
    location: loc(50.4501234, 30.5234567, ele: 179.5, t: DateTime.utc(2026, 10, 9, 8, 30).millisecondsSinceEpoch),
    userMetadata: const LandmarkMetadata(
      entries: {'name': 'Bunker & Co', 'comment': 'north', 'description': 'concrete', 'icon': 'flag', 'color': 0xFF00FF00},
    ),
  );

  test('waypoint round-trip keeps every field', () {
    final back = parser.parse(serializer.serialize([waypoint], const ExportOptions()), separate).single;
    expect(back, waypoint);
  });

  test('track round-trip keeps segments, heights and times', () {
    final track = TrackObject(
      userMetadata: const LandmarkMetadata(entries: {'name': 'Walk'}),
      segments: [
        TrackSegment(locations: [loc(50, 30, ele: 100, t: 1760000000000), loc(50.001, 30.001, ele: 101.25, t: 1760000060000)]),
        TrackSegment(locations: [loc(50.01, 30.01)]),
      ],
    );
    final back = parser.parse(serializer.serialize([track], const ExportOptions()), separate).single;
    expect(back, track);
  });

  test('route round-trip', () {
    final route = RouteObject(
      userMetadata: const LandmarkMetadata(entries: {'name': 'R'}),
      waypoints: [
        WaypointObject(location: loc(50, 30), userMetadata: const LandmarkMetadata(entries: {'name': 'Start'})),
        WaypointObject(location: loc(50.1, 30.1)),
      ],
    );
    expect(parser.parse(serializer.serialize([route], const ExportOptions()), separate).single, route);
  });

  test('without segments a track is one trkseg; track waypoints become wpt', () {
    final track = TrackObject(
      waypoints: [waypoint],
      segments: [
        TrackSegment(locations: [loc(0, 0)]),
        TrackSegment(locations: [loc(1, 1)]),
      ],
    );
    final text = utf8.decode(serializer.serialize([track], const ExportOptions(includeSegments: false)));
    expect('<trkseg>'.allMatches(text), hasLength(1));
    expect(text, contains('<wpt'));
    final noWpt = utf8.decode(serializer.serialize([track], const ExportOptions(includeWaypoints: false)));
    expect(noWpt, isNot(contains('<wpt')));
  });

  test('sets and areas are skipped with a warning', () {
    final warnings = <String>[];
    final text = utf8.decode(serializer.serialize([const SetObject(), const AreaObject()], const ExportOptions(), onWarning: warnings.add));
    expect(warnings, hasLength(2));
    expect(text, contains('<gpx'));
  });

  test('elevation none omits heights', () {
    final text = utf8.decode(
      serializer.serialize([waypoint], const ExportOptions(extras: {GpxSerializer.elevationSource: 'none'})),
    );
    expect(text, isNot(contains('<ele>')));
  });
}
