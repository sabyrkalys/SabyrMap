import 'dart:typed_data';

import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/formats/kml/kml_parser.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const String kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <Style id="red"><LineStyle><color>ff0000ff</color></LineStyle></Style>
  <Style id="pin"><IconStyle><color>ff00ff00</color><Icon><href>tent</href></Icon></IconStyle></Style>
  <StyleMap id="pinMap"><Pair><key>normal</key><styleUrl>#pin</styleUrl></Pair></StyleMap>
  <Placemark><name>Camp</name><description>by the river</description><styleUrl>#pinMap</styleUrl>
    <Point><coordinates>30.5,50.4,150</coordinates></Point></Placemark>
  <Placemark><name>Road</name><styleUrl>#red</styleUrl>
    <LineString><coordinates>30,50 30.1,50.1
      30.2,50.2</coordinates></LineString></Placemark>
  <Placemark><name>Field</name>
    <Polygon>
      <outerBoundaryIs><LinearRing><coordinates>30,50 30.01,50 30.01,50.01 30,50.01 30,50</coordinates></LinearRing></outerBoundaryIs>
      <innerBoundaryIs><LinearRing><coordinates>30.002,50.002 30.004,50.002 30.004,50.004 30.002,50.002</coordinates></LinearRing></innerBoundaryIs>
    </Polygon></Placemark>
  <Folder><Placemark><name>Mixed</name>
    <MultiGeometry>
      <Point><coordinates>31,51</coordinates></Point>
      <LineString><coordinates>31,51 31.1,51.1</coordinates></LineString>
      <LineString><coordinates>32,52 32.1,52.1</coordinates></LineString>
      <Polygon><outerBoundaryIs><LinearRing><coordinates>33,53 33.1,53 33.1,53.1 33,53</coordinates></LinearRing></outerBoundaryIs></Polygon>
    </MultiGeometry></Placemark></Folder>
  <Placemark><name>Empty</name></Placemark>
</Document>
</kml>''';

void main() {
  const parser = KmlParser();
  late List<LandmarkObject> objects;
  late List<String> warnings;
  setUp(() {
    warnings = [];
    objects = parser.parse(bytesOf(kml), const ImportOptions(), onWarning: warnings.add);
  });

  test('Point becomes a waypoint with name, description, height', () {
    final camp = objects.first as WaypointObject;
    expect(camp.userMetadata.name, 'Camp');
    expect(camp.userMetadata.description, 'by the river');
    expect((camp.location.latitude, camp.location.longitude), (50.4, 30.5));
    expect(FormatSupport.elevationOf(camp.location), 150);
  });

  test('LineString becomes a one-segment track', () {
    final road = objects[1] as TrackObject;
    expect(road.userMetadata.name, 'Road');
    expect(road.segments.single.locations, hasLength(3));
  });

  test('Polygon becomes an area with holes, without the closing point', () {
    final field = objects[2] as AreaObject;
    expect(field.polygons.single.outline, hasLength(4));
    expect(field.polygons.single.holes.single, hasLength(3));
  });

  test('MultiGeometry is split by kind', () {
    final mixed = objects.sublist(3);
    expect(mixed.map((o) => o.type), [LandmarkType.waypoint, LandmarkType.track, LandmarkType.area]);
    expect((mixed[1] as TrackObject).segments, hasLength(2));
    expect(mixed.every((o) => o.userMetadata.name == 'Mixed'), isTrue);
  });

  test('styles: line colour and icon go to metadata', () {
    expect(objects[1].userMetadata.colorValue, 0xFFFF0000);
    expect(objects.first.userMetadata.colorValue, 0xFF00FF00);
    expect(objects.first.userMetadata.iconId, 'tent');
  });

  test('a placemark without geometry is a warning', () {
    expect(objects, hasLength(6));
    expect(warnings.single, contains('no geometry'));
  });

  test('KMZ is unpacked', () {
    final kmz = ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('doc.kml', bytesOf(kml))));
    expect(parser.parse(Uint8List.fromList(kmz), const ImportOptions()), hasLength(6));
    final empty = ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('a.txt', bytesOf('x'))));
    expect(() => parser.parse(Uint8List.fromList(empty), const ImportOptions()), throwsFormatException);
  });

  test('not KML throws FormatException', () {
    expect(() => parser.parse(bytesOf('<gpx/>'), const ImportOptions()), throwsFormatException);
    expect(() => parser.parse(bytesOf('<kml><Document>'), const ImportOptions()), throwsFormatException);
  });
}
