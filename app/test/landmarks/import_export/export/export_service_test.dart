import 'dart:io';

import 'package:app/landmarks/composite/drafts/set_draft.dart';
import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/export/export_request.dart';
import 'package:app/landmarks/import_export/formats/kml/kml_serializer.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../services/fixture.dart';
import '../helpers.dart';

void main() {
  late ServicesFixture f;
  late String target;
  setUp(() async {
    f = await ServicesFixture.create();
    target = p.join(f.root.path, 'exports');
  });
  tearDown(() => f.dispose());

  final waypoint = WaypointObject(
    location: loc(50.45, 30.52),
    userMetadata: const LandmarkMetadata(entries: {'name': 'Bunker'}),
  );
  final track = TrackObject(
    userMetadata: const LandmarkMetadata(entries: {'name': 'Walk'}),
    segments: [TrackSegment(locations: [loc(50, 30), loc(50.1, 30.1)])],
  );

  ExportRequest request(List<LandmarkObject> objects, String format, {String? name, ExportOptions? options}) =>
      ExportRequest(
        objects: objects,
        format: f.services.formatRegistry.byId(format)!,
        options: options ?? const ExportOptions(),
        targetFolder: target,
        preferredFilename: name,
      );

  test('a waypoint to GPX: file created, contains <wpt>', () async {
    final result = await f.services.exportService.export(request([waypoint], 'gpx'));
    expect(result.success, isTrue);
    expect(result.exportedCount, 1);
    expect(p.dirname(result.filePath!), target);
    expect(p.basename(result.filePath!), 'bunker_1760000000000.gpx');
    expect(File(result.filePath!).readAsStringSync(), contains('<wpt lat="50.45" lon="30.52">'));
  });

  test('a track to KML contains <LineString>; KMZ gets .kmz', () async {
    final kml = await f.services.exportService.export(request([track], 'kml'));
    expect(File(kml.filePath!).readAsStringSync(), contains('<LineString>'));
    final kmz = await f.services.exportService.export(
      request([track], 'kml', options: const ExportOptions(extras: {KmlSerializer.asKmz: true})),
    );
    expect(p.extension(kmz.filePath!), '.kmz');
  });

  test('a format that cannot export, or cannot hold the type, fails with a message', () async {
    final geojson = await f.services.exportService.export(request([waypoint], 'geojson'));
    expect(geojson.success, isFalse);
    expect(geojson.errorMessage, contains('GeoJSON'));
    final area = await f.services.exportService.export(request([const AreaObject()], 'gpx'));
    expect(area.success, isFalse);
    expect(area.warnings.single, contains('are'));
    expect(Directory(target).existsSync(), isFalse);
  });

  test('unsupported types are skipped, the rest exported', () async {
    final result = await f.services.exportService.export(request([waypoint, const AreaObject(), track], 'gpx'));
    expect(result.success, isTrue);
    expect(result.exportedCount, 2);
    expect(result.warnings, hasLength(1));
    expect(p.basename(result.filePath!), startsWith('landmarks_'));
  });

  test('name collisions get _1, _2', () async {
    final names = [
      for (var i = 0; i < 3; i++) p.basename((await f.services.exportService.export(request([waypoint], 'gpx', name: 'trip'))).filePath!),
    ];
    expect(names, ['trip.gpx', 'trip_1.gpx', 'trip_2.gpx']);
  });

  test('export does not change the source object or file', () async {
    final path = await f.services.creation.create(
      const MarkerDraft(type: LandmarkType.waypoint, longitude: 30.52, latitude: 50.45, name: 'Bunker'),
    );
    final before = File(path).readAsBytesSync();
    final loaded = (await f.services.repository.load(path)).content;
    final result = await f.services.exportService.exportToFile([path], 'kml', targetFolder: target);
    expect(result.success, isTrue);
    expect(File(path).readAsBytesSync(), before);
    expect((await f.services.repository.load(path)).content, loaded);
  });

  test('exportToFile: unknown format, unreadable files', () async {
    expect((await f.services.exportService.exportToFile([], 'shp')).success, isFalse);
    final set = await f.services.compositeCreation.createSet(SetDraft(initialWaypoints: [loc(0, 0)]), loc(0, 0));
    final result = await f.services.exportService.exportToFile([p.join(f.root.path, 'none.wpt'), set], 'csv');
    expect(result.success, isFalse);
    expect(result.warnings, hasLength(2));
  });

  test('exportToFile defaults to the default folder; CSV gets .csv', () async {
    final path = await f.services.creation.create(const MarkerDraft(type: LandmarkType.waypoint, longitude: 30.52, latitude: 50.45, name: 'Bunker'));
    final result = await f.services.exportService.exportToFile([path], 'csv');
    expect(p.dirname(result.filePath!), f.paths.importDefault);
    expect(p.extension(result.filePath!), '.csv');
  });
}
