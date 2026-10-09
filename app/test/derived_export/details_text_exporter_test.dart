import 'dart:io';

import 'package:app/derived_export/details_image_exporter.dart';
import 'package:app/derived_export/details_text_exporter.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

LandmarkLocation loc(double lat, double lon, {double? ele, int? t}) => LandmarkLocation(
  latitude: lat,
  longitude: lon,
  values: [
    if (ele != null) LocationValue(type: LocationValueType.elevation, value: (ele * 1000).round()),
    if (t != null) LocationValue(type: LocationValueType.utcTime, value: t),
  ],
);

void main() {
  late Directory root;
  late StoragePaths paths;
  late StorageService storage;
  setUp(() {
    root = Directory.systemTemp.createTempSync('details_');
    paths = StoragePaths.forRoot(root.path);
    storage = StorageService(paths);
  });
  tearDown(() => root.deleteSync(recursive: true));

  final waypoint = WaypointObject(
    location: loc(50.45, 30.52, ele: 179),
    userMetadata: const LandmarkMetadata(entries: {'name': 'Bunker', 'comment': 'north entrance'}),
  );
  final track = TrackObject(
    userMetadata: const LandmarkMetadata(entries: {'name': 'Walk', 'created_at': 1760000000000}),
    segments: [
      TrackSegment(
        locations: [
          loc(50, 30, ele: 100, t: 1760000000000),
          loc(50.01, 30, ele: 150, t: 1760001800000),
          loc(50.02, 30, ele: 120, t: 1760003600000),
        ],
      ),
    ],
  );

  test('a waypoint file contains its name and position', () async {
    final path = await DetailsTextExporter(paths, storage).export(waypoint, p.join(root.path, 'out'));
    expect(p.basename(path), 'bunker_details.txt');
    final text = File(path).readAsStringSync();
    expect(text, contains('Bunker'));
    expect(text, contains('north entrance'));
    expect(text, contains('50.450000'));
    expect(text, contains('179.0 m'));
  });

  test('a track file has the statistics, heights, speed and events sections', () async {
    final path = await DetailsTextExporter(paths, storage).export(track, root.path);
    final text = File(path).readAsStringSync();
    expect(text, contains('Статистика'));
    expect(text, contains('Высоты'));
    expect(text, contains('Набор: 50 m'));
    expect(text, contains('Скорости'));
    expect(text, contains('Длительность: 1:00:00'));
    expect(text, contains('2025-10-09'));
  });

  test('the locale comes from settings; names collide into _1', () async {
    final exporter = DetailsTextExporter(paths, storage, locale: () => 'en');
    final first = await exporter.export(track, root.path, preferredFilename: 'Report');
    final second = await exporter.export(track, root.path, preferredFilename: 'Report');
    expect(p.basename(first), 'report_details.txt');
    expect(p.basename(second), 'report_details_1.txt');
    expect(File(first).readAsStringSync(), contains('Statistics'));
  });

  test('sets, routes and areas render too', () async {
    final exporter = DetailsTextExporter(paths, storage);
    for (final object in <LandmarkObject>[
      SetObject(waypoints: [waypoint]),
      RouteObject(waypoints: [waypoint, waypoint]),
      AreaObject(polygons: [AreaPolygon(outline: [loc(0, 0), loc(0, 0.01), loc(0.01, 0.01)])]),
    ]) {
      final text = File(await exporter.export(object, root.path)).readAsStringSync();
      expect(text, contains('Статистика'));
    }
  });

  test('the image exporter is not available yet', () async {
    await expectLater(DetailsImageExporter(paths, storage).export(waypoint, root.path), throwsUnsupportedError);
  });
}
