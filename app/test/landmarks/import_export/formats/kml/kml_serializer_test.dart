import 'dart:convert';

import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/formats/kml/kml_parser.dart';
import 'package:app/landmarks/import_export/formats/kml/kml_serializer.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  const serializer = KmlSerializer();
  const parser = KmlParser();
  List<LandmarkObject> roundTrip(List<LandmarkObject> objects, [ExportOptions options = const ExportOptions()]) =>
      parser.parse(serializer.serialize(objects, options), const ImportOptions());

  test('waypoint round-trip: coordinates, height, name, description, colour, icon', () {
    final wp = WaypointObject(
      location: loc(50.4501234, 30.5234567, ele: 150.5),
      userMetadata: const LandmarkMetadata(
        entries: {'name': 'Camp', 'description': 'river', 'color': 0x80FF8800, 'icon': 'tent'},
      ),
    );
    expect(roundTrip([wp]).single, wp);
  });

  test('track round-trip: one segment and several (MultiGeometry)', () {
    final one = TrackObject(
      userMetadata: const LandmarkMetadata(entries: {'name': 'Road', 'color': 0xFFFF0000}),
      segments: [TrackSegment(locations: [loc(50, 30), loc(50.1, 30.1, ele: 12)])],
    );
    expect(roundTrip([one]).single, one);
    final two = TrackObject(
      userMetadata: const LandmarkMetadata(entries: {'name': 'Two'}),
      segments: [
        TrackSegment(locations: [loc(50, 30), loc(50.1, 30.1)]),
        TrackSegment(locations: [loc(51, 31), loc(51.1, 31.1)]),
      ],
    );
    expect(utf8.decode(serializer.serialize([two], const ExportOptions())), contains('<MultiGeometry>'));
    expect(roundTrip([two]).single, two);
  });

  test('area round-trip with a hole', () {
    final area = AreaObject(
      userMetadata: const LandmarkMetadata(entries: {'name': 'Field'}),
      polygons: [
        AreaPolygon(
          outline: [loc(50, 30), loc(50, 30.01), loc(50.01, 30.01), loc(50.01, 30)],
          holes: [
            [loc(50.002, 30.002), loc(50.002, 30.004), loc(50.004, 30.004)],
          ],
        ),
      ],
    );
    expect(roundTrip([area]).single, area);
  });

  test('a route is written as a LineString', () {
    final route = RouteObject(waypoints: [WaypointObject(location: loc(0, 0)), WaypointObject(location: loc(1, 1))]);
    final text = utf8.decode(serializer.serialize([route], const ExportOptions()));
    expect(text, contains('<LineString>'));
    expect(text, contains('0,0 1,1'));
  });

  test('KMZ option zips the document; embedPictures only warns', () {
    final warnings = <String>[];
    final wp = WaypointObject(location: loc(1, 2));
    final kmz = serializer.serialize(
      [wp],
      const ExportOptions(extras: {KmlSerializer.asKmz: true, KmlSerializer.embedPictures: true}),
      onWarning: warnings.add,
    );
    expect(KmlParser.isZip(kmz), isTrue);
    expect(parser.parse(kmz, const ImportOptions()).single, wp);
    expect(warnings.single, contains('not supported'));
  });

  test('sets are skipped with a warning', () {
    final warnings = <String>[];
    serializer.serialize([const SetObject()], const ExportOptions(), onWarning: warnings.add);
    expect(warnings, hasLength(1));
  });

  test('colour conversion both ways', () {
    expect(KmlSerializer.argbToKmlColor(0x80112233), '80332211');
    expect(KmlParser.kmlColorToArgb('80332211'), 0x80112233);
  });
}
