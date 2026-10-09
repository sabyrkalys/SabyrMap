import 'dart:convert';

import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/formats/csv/csv_parser.dart';
import 'package:app/landmarks/import_export/formats/csv/csv_serializer.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/import_export/utils/charset_detector.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  const serializer = CsvSerializer();
  final t = DateTime.utc(2026, 10, 9, 8, 30).millisecondsSinceEpoch;
  final waypoint = WaypointObject(
    location: loc(50.45, 30.52, ele: 150.5, t: t),
    userMetadata: const LandmarkMetadata(entries: {'name': 'Camp, north', 'comment': 'river'}),
  );
  String write(List<LandmarkObject> objects, [Map<String, Object?> extras = const {}, ExportOptions? options]) =>
      utf8.decode(serializer.serialize(objects, (options ?? const ExportOptions()).copyWith(extras: extras)));

  test('default columns, quoting and ISO time', () {
    expect(
      write([waypoint]),
      'name,latitude,longitude,elevation,time,comment\n"Camp, north",50.45,30.52,150.5,2026-10-09T08:30:00Z,river\n',
    );
  });

  test('columns are chosen by the option; unknown ones are dropped', () {
    final warnings = <String>[];
    final text = utf8.decode(
      serializer.serialize(
        [waypoint],
        const ExportOptions(extras: {CsvSerializer.columns: ['latitude', 'longitude', 'colour']}),
        onWarning: warnings.add,
      ),
    );
    expect(text, 'latitude,longitude\n50.45,30.52\n');
    expect(warnings.single, contains('colour'));
  });

  test('unix time format, semicolon, no headers', () {
    expect(
      write([waypoint], {
        CsvSerializer.timeFormat: 'unix',
        CsvSerializer.separator: ';',
        CsvSerializer.headersInFirstRow: false,
        CsvSerializer.columns: ['name', 'time'],
      }),
      'Camp, north;$t\n',
    );
  });

  test('a track gives one row per point with the segment number', () {
    final track = TrackObject(
      userMetadata: const LandmarkMetadata(entries: {'name': 'Walk'}),
      segments: [
        TrackSegment(locations: [loc(1, 1), loc(2, 2)]),
        TrackSegment(locations: [loc(3, 3)]),
      ],
    );
    expect(
      write([track], {CsvSerializer.columns: ['segment', 'latitude']}),
      'segment,latitude\n0,1\n0,2\n1,3\n',
    );
  });

  test('round-trip through the parser', () {
    final back = const CsvParser().parse(serializer.serialize([waypoint], const ExportOptions()), const ImportOptions());
    expect(back.single, waypoint);
  });

  test('cp1251 charset and unsupported types', () {
    final warnings = <String>[];
    final bytes = serializer.serialize(
      [WaypointObject(location: loc(1, 2), userMetadata: const LandmarkMetadata(entries: {'name': 'Лагерь'})), const AreaObject()],
      const ExportOptions(charset: 'cp1251'),
      onWarning: warnings.add,
    );
    expect(CharsetDetector.decode(bytes, charset: 'cp1251'), contains('Лагерь'));
    expect(warnings, hasLength(1));
  });
}
