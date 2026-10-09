import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/formats/geojson/geojson_parser.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const String collection = '''{
  "type": "FeatureCollection",
  "features": [
    {"type": "Feature", "properties": {"name": "Camp", "description": "river", "color": "#FF8800"},
     "geometry": {"type": "Point", "coordinates": [30.5, 50.4, 150]}},
    {"type": "Feature", "properties": {"name": "Road"},
     "geometry": {"type": "LineString", "coordinates": [[30, 50], [30.1, 50.1]]}},
    {"type": "Feature", "properties": {"name": "Two", "color": 4278190335},
     "geometry": {"type": "MultiLineString", "coordinates": [[[30, 50], [30.1, 50.1]], [[31, 51], [31.1, 51.1]]]}},
    {"type": "Feature", "properties": null,
     "geometry": {"type": "Polygon", "coordinates": [
       [[30, 50], [30.01, 50], [30.01, 50.01], [30, 50]],
       [[30.002, 50.002], [30.004, 50.002], [30.004, 50.004], [30.002, 50.002]]]}},
    {"type": "Feature", "properties": {}, "geometry": {"type": "MultiPolygon", "coordinates": [
       [[[30, 50], [30.01, 50], [30.01, 50.01], [30, 50]]],
       [[[31, 51], [31.01, 51], [31.01, 51.01], [31, 51]]]]}},
    {"type": "Feature", "properties": {}, "geometry": {"type": "Point", "coordinates": [30]}},
    {"type": "Feature", "properties": {}, "geometry": null}
  ]
}''';

void main() {
  const parser = GeoJsonParser();
  late List<LandmarkObject> objects;
  late List<String> warnings;
  setUp(() {
    warnings = [];
    objects = parser.parse(bytesOf(collection), const ImportOptions(), onWarning: warnings.add);
  });

  test('Point, LineString, MultiLineString, Polygon, MultiPolygon', () {
    expect(objects.map((o) => o.type), [
      LandmarkType.waypoint,
      LandmarkType.track,
      LandmarkType.track,
      LandmarkType.area,
      LandmarkType.area,
    ]);
    final camp = objects.first as WaypointObject;
    expect((camp.location.latitude, camp.location.longitude), (50.4, 30.5));
    expect(FormatSupport.elevationOf(camp.location), 150);
    expect((objects[1] as TrackObject).segments.single.locations, hasLength(2));
    expect((objects[2] as TrackObject).segments, hasLength(2));
    final area = objects[3] as AreaObject;
    expect(area.polygons.single.outline, hasLength(3));
    expect(area.polygons.single.holes.single, hasLength(3));
    expect((objects[4] as AreaObject).polygons, hasLength(2));
  });

  test('properties go to metadata', () {
    expect(objects.first.userMetadata.name, 'Camp');
    expect(objects.first.userMetadata.description, 'river');
    expect(objects.first.userMetadata.colorValue, 0xFFFF8800);
    expect(objects[2].userMetadata.colorValue, 0xFF0000FF);
    expect(objects[3].userMetadata.entries, isEmpty);
  });

  test('bad features are warnings', () {
    expect(warnings, hasLength(2));
  });

  test('a single Feature or bare geometry; invalid JSON throws', () {
    expect(parser.parse(bytesOf('{"type":"Point","coordinates":[1,2]}'), const ImportOptions()).single, isA<WaypointObject>());
    expect(
      parser.parse(bytesOf('{"type":"Feature","properties":{"name":"x"},"geometry":{"type":"Point","coordinates":[1,2]}}'), const ImportOptions()).single.userMetadata.name,
      'x',
    );
    expect(() => parser.parse(bytesOf('{broken'), const ImportOptions()), throwsFormatException);
    expect(() => parser.parse(bytesOf('[1,2]'), const ImportOptions()), throwsFormatException);
  });
}
