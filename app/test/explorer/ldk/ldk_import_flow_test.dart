import 'dart:convert';
import 'dart:io';

import 'package:app/explorer/ldk/ldk_import_flow.dart';
import 'package:app/landmarks/import_export/import/import_result.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../landmarks/services/fixture.dart';
import '../landmark_test_helpers.dart';

const _gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="42.87" lon="74.60"><name>Перевал</name></wpt>
  <trk><name>Подъём</name><trkseg>
    <trkpt lat="42.80" lon="74.50"/><trkpt lat="42.81" lon="74.51"/>
  </trkseg></trk>
</gpx>''';

const _kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
  <Placemark><name>Лагерь</name><Point><coordinates>74.6,42.87,0</coordinates></Point></Placemark>
  <Placemark><name>Тропа</name><LineString><coordinates>74.5,42.8,0 74.51,42.81,0</coordinates></LineString></Placemark>
</Document></kml>''';

void main() {
  late ServicesFixture f;
  late String inbox;
  late String target;

  setUp(() async {
    f = await ServicesFixture.create();
    inbox = p.join(f.root.path, 'inbox');
    target = p.join(f.paths.landmarks, 'Импорт');
    Directory(inbox).createSync();
  });
  tearDown(() => f.root.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final path = p.join(inbox, name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  void expectNativeFiles(ImportResult result) {
    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.createdPaths, isNotEmpty);
    for (final path in result.createdPaths) {
      expect(File(path).existsSync(), isTrue);
      expect(p.dirname(path), target);
      expect(LandmarkType.fromExtension(p.extension(path)), isNotNull, reason: path);
    }
  }

  test('GPX import creates a .trk with the point attached (default options)', () async {
    final result = await LdkImportFlow.importFile(f.services, write('day.gpx', utf8.encode(_gpx)), target);
    expectNativeFiles(result);
    expect(result.createdTypes, [LandmarkType.track]);
    final track = (await f.services.repository.load(result.createdPaths.single)).content as TrackObject;
    expect(track.userMetadata.name, 'Подъём');
    expect(track.waypoints.single.userMetadata.name, 'Перевал');
  });

  test('GPX with only points creates .wpt files', () async {
    const points = '<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">'
        '<wpt lat="42.87" lon="74.60"><name>Перевал</name></wpt>'
        '<wpt lat="42.88" lon="74.61"><name>Озеро</name></wpt></gpx>';
    final result = await LdkImportFlow.importFile(f.services, write('points.gpx', utf8.encode(points)), target);
    expectNativeFiles(result);
    expect(result.createdTypes, [LandmarkType.waypoint, LandmarkType.waypoint]);
  });

  test('KMZ import creates landmark files the same way', () async {
    final kml = utf8.encode(_kml);
    final kmz = ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('doc.kml', kml)));
    final result = await LdkImportFlow.importFile(f.services, write('day.kmz', kmz), target);
    expectNativeFiles(result);
    expect(result.createdTypes, contains(LandmarkType.waypoint));
    expect(result.createdTypes.length, 2);
  });

  test('an .ldk from outside is checked and copied as is', () async {
    final source = await createLdk(f.services, 'Поход', folder: inbox);
    final result = await LdkImportFlow.importFile(f.services, source, target);
    expectNativeFiles(result);
    expect(result.createdTypes, [LandmarkType.ldkFile]);
    expect(File(result.createdPaths.single).readAsBytesSync(), File(source).readAsBytesSync());
    // Повторный импорт не перезаписывает, а получает суффикс.
    final again = await LdkImportFlow.importFile(f.services, source, target);
    expect(again.createdPaths.single, isNot(result.createdPaths.single));
  });

  test('a damaged .ldk is refused', () async {
    final result = await LdkImportFlow.importFile(f.services, write('bad.ldk', [1, 2, 3]), target);
    expect(result.success, isFalse);
    expect(Directory(target).existsSync() && Directory(target).listSync().isNotEmpty, isFalse);
  });

  testWidgets('the UI shows progress, then the result', (tester) async {
    late String source;
    ImportResult? result;
    // Свой каталог: общий из setUp удаляется в tearDown.
    await tester.runAsync(() async {
      source = p.join(inbox, 'day.gpx');
      File(source).writeAsStringSync(_gpx);
    });
    await tester.pumpWidget(
      hostApp(f.services, (context) async => result = await LdkImportFlow.run(context, f.services, source, target)),
    );
    await tester.tap(find.byKey(const Key('host_button')));
    await tester.pump();
    expect(find.byKey(const Key('ldk_import_progress')), findsOneWidget);
    expect(find.text('Импорт «day.gpx»...'), findsOneWidget);
    for (var i = 0; i < 100 && result == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ldk_import_progress')), findsNothing);
    expect(find.text('Импортировано: 1'), findsOneWidget);
  });
}
