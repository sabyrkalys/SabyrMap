import 'dart:io';

import 'package:app/landmarks/import_export/formats/gpx/gpx_parser.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/import_export/import/import_request.dart';
import 'package:app/landmarks/import_export/registry/format_descriptor.dart';
import 'package:app/landmarks/import_export/utils/charset_detector.dart';
import 'package:app/landmarks/import_export/utils/elevation_source.dart';
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
    target = p.join(f.paths.landmarks, 'imported_gpx');
  });
  tearDown(() => f.dispose());

  ImportRequest gpx(String text, {ImportOptions options = const ImportOptions()}) => ImportRequest(
    bytes: bytesOf(text),
    sourcePath: '/sdcard/Download/trip.gpx',
    format: f.services.formatRegistry.byId('gpx')!,
    options: options,
    targetFolder: target,
  );

  test('a valid GPX waypoint is saved into the target folder', () async {
    final result = await f.services.importService.import(
      gpx('<gpx><wpt lat="50.45" lon="30.52"><name>Bunker</name></wpt></gpx>'),
    );
    expect(result.success, isTrue);
    expect(result.importedCount, 1);
    expect(result.createdTypes, [LandmarkType.waypoint]);
    final path = result.createdPaths.single;
    expect(p.dirname(path), target);
    expect(p.basename(path), startsWith('bunker_'));
    final wp = (await f.services.repository.load(path)).content as WaypointObject;
    expect(wp.userMetadata.name, 'Bunker');
    expect(wp.userMetadata.createdAtMs, 1760000000000);
    expect(wp.userMetadata.version, 0);
  });

  test('several objects give several files with statistics', () async {
    final result = await f.services.importService.import(
      gpx(sampleGpx, options: const ImportOptions(extras: {GpxParser.includeWaypointsInTrack: false})),
    );
    expect(result.importedCount, 4);
    expect(result.createdTypes, [LandmarkType.waypoint, LandmarkType.waypoint, LandmarkType.route, LandmarkType.track]);
    expect(result.createdPaths.toSet(), hasLength(4));
    final track = (await f.services.repository.load(result.createdPaths.last)).content;
    expect(track.userMetadata.entries['length_m'], greaterThan(0));
    expect(track.userMetadata.entries['duration_ms'], 60000);
  });

  test('options.folder wins over the request folder', () async {
    final other = p.join(f.paths.landmarks, 'other');
    final result = await f.services.importService.import(
      gpx('<gpx><wpt lat="1" lon="2"/></gpx>', options: ImportOptions(folder: other)),
    );
    expect(p.dirname(result.createdPaths.single), other);
  });

  test('a parse error fails the import and creates nothing', () async {
    final result = await f.services.importService.import(gpx('<gpx><wpt'));
    expect(result.success, isFalse);
    expect(result.errorMessage, contains('trip.gpx'));
    expect(Directory(target).existsSync(), isFalse);
  });

  test('bad objects are warnings, the rest are imported', () async {
    final result = await f.services.importService.import(
      gpx('<gpx><wpt lat="x" lon="2"/><wpt lat="1" lon="2"><name>${'a' * 300}</name></wpt><wpt lat="1" lon="2"/></gpx>'),
    );
    expect(result.success, isTrue);
    expect(result.importedCount, 1);
    expect(result.warnings, hasLength(2));
  });

  test('egm96 adds a warning; an empty file is a success with a warning', () async {
    final egm = await f.services.importService.import(
      gpx('<gpx><wpt lat="1" lon="2"/></gpx>', options: const ImportOptions(elevation: ElevationSource.egm96)),
    );
    expect(egm.warnings.single, contains('EGM96'));
    final empty = await f.services.importService.import(gpx('<gpx/>'));
    expect(empty.success, isTrue);
    expect(empty.importedCount, 0);
    expect(empty.warnings.single, contains('No objects'));
  });

  test('a format without an importer fails', () async {
    final result = await f.services.importService.import(
      ImportRequest(
        bytes: bytesOf(''),
        sourcePath: 'x',
        format: FormatDescriptor(id: 'none', displayName: 'None', extensions: const ['none'], capabilities: const {}),
        targetFolder: target,
      ),
    );
    expect(result.success, isFalse);
  });

  test('importFromFile: format by extension, cp1251 auto-detected, source untouched', () async {
    final source = File(p.join(f.root.path, 'points.csv'));
    final bytes = CharsetDetector.encode('name;lat;lon\nЛагерь у реки;50.1;30.2\nБлиндаж;50.2;30.3\n', charset: 'cp1251');
    source.writeAsBytesSync(bytes);
    final result = await f.services.importService.importFromFile(source.path);
    expect(result.success, isTrue);
    expect(p.dirname(result.createdPaths.first), f.paths.importDefault);
    final names = [
      for (final path in result.createdPaths) (await f.services.repository.load(path)).content.userMetadata.name,
    ];
    expect(names, ['Лагерь у реки', 'Блиндаж']);
    expect(source.readAsBytesSync(), bytes);
  });

  test('importFromFile: unknown extension and missing file fail', () async {
    expect((await f.services.importService.importFromFile('/x/file.dxf')).success, isFalse);
    expect((await f.services.importService.importFromFile(p.join(f.root.path, 'none.gpx'))).success, isFalse);
  });

  test('defaultOptions come from the format schema', () async {
    final options = await f.services.importService.defaultOptions(f.services.formatRegistry.byId('gpx')!);
    expect(options.extras[GpxParser.includeWaypointsInTrack], isTrue);
    expect(options.elevation, ElevationSource.wgs84);
  });
}
