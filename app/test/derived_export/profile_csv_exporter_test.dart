import 'dart:io';

import 'package:app/derived_export/profile_csv_exporter.dart';
import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late ProfileCsvExporter exporter;
  setUp(() {
    root = Directory.systemTemp.createTempSync('profile_');
    final paths = StoragePaths.forRoot(root.path);
    exporter = ProfileCsvExporter(paths, StorageService(paths));
  });
  tearDown(() => root.deleteSync(recursive: true));

  LandmarkLocation loc(double lat, double lon, {double? ele, int? t}) => LandmarkLocation(
    latitude: lat,
    longitude: lon,
    values: [
      if (ele != null) LocationValue(type: LocationValueType.elevation, value: (ele * 1000).round()),
      if (t != null) LocationValue(type: LocationValueType.utcTime, value: t),
    ],
  );

  test('3 points give a header and 3 rows with the right columns', () async {
    final points = [loc(50, 30, ele: 100, t: 1000), loc(50.01, 30, ele: 110.5, t: 2000), loc(50.02, 30)];
    final track = TrackObject(
      userMetadata: const LandmarkMetadata(entries: {'name': 'Walk'}),
      segments: [TrackSegment(locations: points)],
    );
    final path = await exporter.export(track, root.path);
    expect(p.basename(path), 'walk_profile.csv');
    final lines = File(path).readAsLinesSync().where((l) => l.isNotEmpty).toList();
    expect(lines, hasLength(4));
    expect(lines.first, 'distance_m,elevation_m,lat,lon,time_ms');
    expect(lines[1], '0.0,100.0,50.0000000,30.0000000,1000');
    final d1 = Haversine.distance(points[0], points[1]);
    expect(lines[2], '${d1.toStringAsFixed(1)},110.5,50.0100000,30.0000000,2000');
    final d2 = d1 + Haversine.distance(points[1], points[2]);
    expect(lines[3], '${d2.toStringAsFixed(1)},,50.0200000,30.0000000,');
  });

  test('the gap between segments adds no distance', () async {
    final track = TrackObject(
      segments: [
        TrackSegment(locations: [loc(0, 0), loc(0, 0.001)]),
        TrackSegment(locations: [loc(10, 10)]),
      ],
    );
    final lines = File(await exporter.export(track, root.path, preferredFilename: 'gap')).readAsLinesSync();
    expect(lines[3].split(',').first, lines[2].split(',').first);
  });
}
