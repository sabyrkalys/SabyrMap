import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/formats/gpx/gpx_parser.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/import_export/utils/elevation_source.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  const parser = GpxParser();
  const separate = ImportOptions(extras: {GpxParser.includeWaypointsInTrack: false});

  test('wpt, rte and trk are recognised', () {
    final objects = parser.parse(bytesOf(sampleGpx), separate);
    expect(objects.map((o) => o.type), [LandmarkType.waypoint, LandmarkType.waypoint, LandmarkType.route, LandmarkType.track]);
    final route = objects[2] as RouteObject;
    expect(route.userMetadata.name, 'Route A');
    expect(route.waypoints.first.userMetadata.name, 'Start');
    final track = objects[3] as TrackObject;
    expect(track.userMetadata.name, 'Walk');
    expect([for (final s in track.segments) s.locations.length], [2, 1]);
  });

  test('name, desc, cmt and sym go to metadata; coordinates and height', () {
    final wp = parser.parse(bytesOf(sampleGpx), separate).first as WaypointObject;
    expect(wp.userMetadata.name, 'Bunker');
    expect(wp.userMetadata.comment, 'north entrance');
    expect(wp.userMetadata.description, 'concrete');
    expect(wp.userMetadata.iconId, 'flag');
    expect((wp.location.latitude, wp.location.longitude), (50.4501, 30.5234));
    expect(FormatSupport.elevationOf(wp.location), 179.5);
  });

  test('ISO 8601 time becomes utcTime', () {
    final wp = parser.parse(bytesOf(sampleGpx), separate).first as WaypointObject;
    expect(FormatSupport.timeOf(wp.location), DateTime.utc(2026, 10, 9, 8, 30).millisecondsSinceEpoch);
  });

  test('with one track, waypoints are attached to it by default', () {
    final objects = parser.parse(bytesOf(sampleGpx), const ImportOptions());
    expect(objects.map((o) => o.type), [LandmarkType.route, LandmarkType.track]);
    expect((objects.last as TrackObject).waypoints.map((w) => w.userMetadata.name), ['Bunker', 'Post']);
  });

  test('elevation none drops heights', () {
    final wp = parser.parse(bytesOf(sampleGpx), const ImportOptions(elevation: ElevationSource.none, extras: {
      GpxParser.includeWaypointsInTrack: false,
    })).first as WaypointObject;
    expect(FormatSupport.elevationOf(wp.location), isNull);
  });

  test('GPS week rollover fix moves old dates forward by 1024 weeks', () {
    const gpx = '<gpx><wpt lat="1" lon="2"><time>1999-03-01T00:00:00Z</time></wpt></gpx>';
    final fixed = parser.parse(bytesOf(gpx), const ImportOptions(fixGpsWeekRollover: true)).single as WaypointObject;
    expect(
      FormatSupport.timeOf(fixed.location),
      DateTime.utc(1999, 3, 1).millisecondsSinceEpoch + ImportOptions.gpsRolloverMs,
    );
  });

  test('a point with bad coordinates is skipped with a warning', () {
    final warnings = <String>[];
    final objects = parser.parse(
      bytesOf('<gpx><wpt lat="x" lon="2"/><wpt lat="95" lon="2"/><wpt lat="1" lon="2"/></gpx>'),
      const ImportOptions(),
      onWarning: warnings.add,
    );
    expect(objects, hasLength(1));
    expect(warnings, hasLength(2));
  });

  test('broken XML or another root throws FormatException', () {
    expect(() => parser.parse(bytesOf('<gpx><wpt'), const ImportOptions()), throwsFormatException);
    expect(() => parser.parse(bytesOf('<kml/>'), const ImportOptions()), throwsFormatException);
  });
}
