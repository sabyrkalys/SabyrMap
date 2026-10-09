import 'package:app/landmarks/import_export/formats/csv/csv_parser.dart';
import 'package:app/landmarks/import_export/formats/format_support.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  const parser = CsvParser();
  List<LandmarkObject> parse(String text, [Map<String, Object?> extras = const {}, List<String>? warnings]) =>
      parser.parse(bytesOf(text), ImportOptions(extras: extras), onWarning: warnings?.add);

  test('comma, semicolon and tab separators (auto and explicit)', () {
    for (final sep in [',', ';', '\t']) {
      final text = 'name${sep}latitude${sep}longitude\nA${sep}50.1${sep}30.2\nB${sep}50.3${sep}30.4\n';
      final objects = parse(text);
      expect(objects, hasLength(2), reason: 'separator "$sep"');
      expect((objects.first as WaypointObject).location.latitude, 50.1);
      expect(parse(text, {CsvParser.separator: sep == '\t' ? 'tab' : sep}), hasLength(2));
    }
  });

  test('headers: names, synonyms, case; all supported columns', () {
    final objects = parse(
      'Name,Lat,LON,Ele,Time,Comment,Accuracy\n'
      '"Camp, north",50.1,30.2,150.5,2026-10-09T08:30:00Z,"by ""river""",4.5\n',
    );
    final wp = objects.single as WaypointObject;
    expect(wp.userMetadata.name, 'Camp, north');
    expect(wp.userMetadata.comment, 'by "river"');
    expect(FormatSupport.elevationOf(wp.location), 150.5);
    expect(FormatSupport.timeOf(wp.location), DateTime.utc(2026, 10, 9, 8, 30).millisecondsSinceEpoch);
    expect(FormatSupport.accuracyOf(wp.location), 4.5);
  });

  test('latitude/longitude columns accept letters and DMS', () {
    final wp = parse('name,latitude,longitude\nA,"55°45\'21""N",37.6E\n').single as WaypointObject;
    expect(wp.location.latitude, closeTo(55.7558333, 1e-6));
    expect(wp.location.longitude, 37.6);
  });

  test('a coordinates column', () {
    final wp = parse('name;coordinates\nA;"55.7558N, 37.6173E"\n').single as WaypointObject;
    expect((wp.location.latitude, wp.location.longitude), (55.7558, 37.6173));
  });

  test('without a name column it is a track; unix times in seconds and ms', () {
    final track = parse('lat,lon,time\n50,30,1760000000\n50.1,30.1,1760000060000\n').single as TrackObject;
    final points = track.segments.single.locations;
    expect(points, hasLength(2));
    expect(FormatSupport.timeOf(points.first), 1760000000000);
    expect(FormatSupport.timeOf(points.last), 1760000060000);
    expect(parse('name,lat,lon\nA,1,2\n', {CsvParser.importAs: 'track'}).single, isA<TrackObject>());
  });

  test('no headers: columns from the option', () {
    final objects = parse('50.1,30.2,Camp\n', {
      CsvParser.headersInFirstRow: false,
      CsvParser.columns: ['latitude', 'longitude', 'name'],
    });
    expect(objects.single.userMetadata.name, 'Camp');
  });

  test('bad rows are skipped with a warning', () {
    final warnings = <String>[];
    final objects = parse('name,lat,lon\nA,50,30\nB,abc,30\nC,95,30\nD,,30\n', const {}, warnings);
    expect(objects, hasLength(1));
    expect(warnings, hasLength(3));
    expect(warnings.first, startsWith('Line 3'));
  });

  test('missing coordinate columns throw FormatException; empty file is empty', () {
    expect(() => parse('name,comment\nA,b\n'), throwsFormatException);
    expect(parse(''), isEmpty);
  });
}
