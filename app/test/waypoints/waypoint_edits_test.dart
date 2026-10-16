import 'dart:io';

import 'package:app/app/landmark_services_provider.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/waypoints/waypoint_edits.dart';
import 'package:app/waypoints/waypoint_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../landmarks/services/fixture.dart';

void main() {
  late ServicesFixture f;
  late WaypointEdits edits;
  setUp(() async {
    f = await ServicesFixture.create();
    edits = WaypointEdits(f.services);
  });
  tearDown(() => f.dispose());

  test('create writes a .wpt file with the dialog fields, and the index knows it at once', () async {
    final path = await edits.create(
      name: 'Bunker',
      type: 'checkpoint',
      note: 'concrete',
      color: '#FF0000',
      lat: 50.45,
      lng: 30.52,
      iconFileName: 'camp.png',
      extra: {'comment': 'north', 'icon': 'tent'},
    );
    expect(File(path).existsSync(), isTrue);
    expect(p.dirname(path), f.paths.importDefault);
    final item = f.services.index.byPath(path)!;
    expect((item.name, item.kind, item.description, item.colorValue), ('Bunker', 'checkpoint', 'concrete', 0xFFFF0000));
    expect(item.userIcon, 'camp.png');
    expect(item.latitude, closeTo(50.45, 1e-7));
    expect(item.longitude, closeTo(30.52, 1e-7));
    final stored = await f.services.waypoints.load(path);
    expect(stored.userMetadata.comment, 'north');
    expect(stored.userMetadata.iconId, 'tent');
  });

  test('create into a chosen folder; no colour, note or icon stays empty', () async {
    final path = await edits.create(
      name: 'A',
      type: defaultWaypointType,
      note: '',
      color: null,
      lat: 1,
      lng: 2,
      folder: f.paths.landmarks,
    );
    expect(p.dirname(path), f.paths.landmarks);
    final item = f.services.index.byPath(path)!;
    expect(item.colorValue, isNull);
    expect(item.userIcon, isNull);
    expect(item.description ?? '', isEmpty);
  });

  test('update changes name, type, note, colour and icon; null colour and icon clear them', () async {
    final path = await edits.create(
      name: 'A',
      type: 'generic',
      note: 'x',
      color: '#00FF00',
      lat: 1,
      lng: 2,
      iconFileName: 'camp.png',
    );
    await edits.update(path, name: 'B', type: 'checkpoint', note: 'y', color: null, iconFileName: null);
    final item = f.services.index.byPath(path)!;
    expect((item.name, item.kind, item.description, item.colorValue, item.userIcon), ('B', 'checkpoint', 'y', null, null));
    expect((await f.services.waypoints.load(path)).userMetadata.version, 1);

    await edits.update(path, name: 'B', type: 'checkpoint', note: 'y', color: '#0000FF', iconFileName: 'water.svg');
    expect(f.services.index.byPath(path)!.userIcon, 'water.svg');
  });

  test('names lists every waypoint, inside landmark files too', () async {
    await edits.create(name: 'A', type: 'generic', note: '', color: null, lat: 1, lng: 2);
    await edits.create(name: 'B', type: 'generic', note: '', color: null, lat: 1, lng: 2);
    expect(edits.names, unorderedEquals(['A', 'B']));
    expect(f.services.index.byType(LandmarkType.waypoint), hasLength(2));
  });

  test('delete removes the file; bad input is a WaypointException', () async {
    final path = await edits.create(name: 'A', type: 'generic', note: '', color: null, lat: 1, lng: 2);
    await edits.delete(path);
    expect(File(path).existsSync(), isFalse);
    expect(f.services.index.byPath(path), isNull);
    expect(
      () => edits.create(name: 'A', type: 'generic', note: '', color: null, lat: 95, lng: 2),
      throwsA(isA<WaypointException>()),
    );
    expect(
      () => edits.update('${f.root.path}/none.wpt', name: 'x', type: 'generic', note: '', color: null, iconFileName: null),
      throwsA(isA<WaypointException>()),
    );
  });

  test('group folders are shown relative to the app root', () {
    const folders = MarkerGroupFolders(
      unsorted: '/data/app/files/landmarks/imported',
      myMarkers: '/data/app/files/landmarks',
      appRoot: '/data/app/files',
    );
    expect(folders.display(folders.unsorted), 'landmarks/imported');
    expect(folders.display('/elsewhere/x'), '/elsewhere/x');
    expect(const MarkerGroupFolders(unsorted: '/a', myMarkers: '/b').display('/a'), '/a');
  });
}
