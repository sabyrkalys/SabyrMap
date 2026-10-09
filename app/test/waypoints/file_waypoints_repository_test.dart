import 'dart:io';

import 'package:app/app/landmark_services_provider.dart';
import 'package:app/waypoints/file_waypoints_repository.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoint_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../landmarks/services/fixture.dart';

void main() {
  late ServicesFixture f;
  late FileWaypointsRepository repo;
  setUp(() async {
    f = await ServicesFixture.create();
    repo = FileWaypointsRepository(f.services);
  });
  tearDown(() => f.dispose());

  test('create writes a .wpt file and returns the waypoint with its path as id', () async {
    final w = await repo.create(
      name: 'Bunker',
      type: 'checkpoint',
      note: 'concrete',
      color: '#FF0000',
      lat: 50.45,
      lng: 30.52,
      extra: {'comment': 'north', 'icon': 'tent'},
    );
    expect(File(w.id).existsSync(), isTrue);
    expect(p.dirname(w.id), f.paths.importDefault);
    expect((w.name, w.type, w.note, w.color), ('Bunker', 'checkpoint', 'concrete', '#FF0000'));
    expect(w.lat, closeTo(50.45, 1e-7));
    expect(w.lng, closeTo(30.52, 1e-7));
    expect(w.canEdit, isTrue);
    final stored = await f.services.waypoints.load(w.id);
    expect(stored.userMetadata.comment, 'north');
    expect(stored.userMetadata.iconId, 'tent');
  });

  test('create into a chosen folder', () async {
    final w = await repo.create(
      name: 'A',
      type: defaultWaypointType,
      note: '',
      color: null,
      lat: 1,
      lng: 2,
      folder: f.paths.landmarks,
    );
    expect(p.dirname(w.id), f.paths.landmarks);
    expect(w.color, isNull);
    expect(w.note, isNull);
  });

  test('list finds waypoints in subfolders, oldest first, skips other files', () async {
    final a = await repo.create(name: 'A', type: 'generic', note: '', color: null, lat: 1, lng: 2);
    f.now = f.now.add(const Duration(minutes: 1));
    final b = await repo.create(
      name: 'B',
      type: 'generic',
      note: '',
      color: null,
      lat: 1,
      lng: 2,
      folder: p.join(f.paths.landmarks, 'deep', 'er'),
    );
    File(p.join(f.paths.landmarks, 'broken.wpt')).writeAsBytesSync([1, 2, 3]);
    final list = await repo.list();
    expect(list.map((w) => w.id), [a.id, b.id]);
  });

  test('update changes name, type, note and colour; null colour clears it', () async {
    final w = await repo.create(name: 'A', type: 'generic', note: 'x', color: '#00FF00', lat: 1, lng: 2);
    final u = await repo.update(w.id, name: 'B', type: 'checkpoint', note: 'y', color: null);
    expect((u.name, u.type, u.note, u.color), ('B', 'checkpoint', 'y', null));
    expect(u.id, w.id);
    expect((await f.services.waypoints.load(w.id)).userMetadata.version, 1);
  });

  test('delete removes the file; bad input is a WaypointException', () async {
    final w = await repo.create(name: 'A', type: 'generic', note: '', color: null, lat: 1, lng: 2);
    await repo.delete(w.id);
    expect(File(w.id).existsSync(), isFalse);
    expect(await repo.list(), isEmpty);
    expect(
      () => repo.create(name: 'A', type: 'generic', note: '', color: null, lat: 95, lng: 2),
      throwsA(isA<WaypointException>()),
    );
    expect(
      () => repo.update('${f.root.path}/none.wpt', name: 'x', type: 'generic', note: '', color: null),
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
