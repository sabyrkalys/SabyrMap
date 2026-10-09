import 'dart:io';

import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/drafts/waypoint_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fixture.dart';

void main() {
  late ServicesFixture f;
  late String path;
  setUp(() async {
    f = await ServicesFixture.create();
    path = await f.services.creation.create(
      const MarkerDraft(
        type: LandmarkType.waypoint,
        longitude: 30.5,
        latitude: 50.4,
        name: 'Bunker',
        comment: 'старый',
        colorValue: 0xFFFF0000,
        iconId: 'flag',
      ),
    );
    f.now = f.now.add(const Duration(minutes: 1));
  });
  tearDown(() => f.dispose());

  test('load returns the waypoint', () async {
    final w = await f.services.waypoints.load(path);
    expect(w.userMetadata.name, 'Bunker');
    expect(w.location.latitude, 50.4);
  });

  test('load of a non-waypoint file fails', () async {
    final trk = await f.services.repository.save(LandmarkFile.of(const TrackObject()));
    expect(() => f.services.waypoints.load(trk), throwsA(isA<StorageException>()));
  });

  test('update renames, bumps the version and updated_at', () async {
    final w = await f.services.waypoints.update(path, const WaypointPatch(name: 'Блиндаж'));
    expect(w.userMetadata.name, 'Блиндаж');
    expect(w.userMetadata.version, 1);
    expect(w.userMetadata.updatedAtMs, 1760000060000);
    expect(w.userMetadata.createdAtMs, 1760000000000);
    expect(w.userMetadata.comment, 'старый');
    expect(w, await f.services.waypoints.load(path));
  });

  test('a coordinates-only patch moves the point and nothing else', () async {
    final before = await f.services.waypoints.load(path);
    final w = await f.services.waypoints.update(path, const WaypointPatch(latitude: 51.25));
    expect(w.location.latitude, 51.25);
    expect(w.location.longitude, before.location.longitude);
    final keep = Map.of(before.userMetadata.entries)..remove('updated_at');
    final now = Map.of(w.userMetadata.entries)..remove('updated_at');
    expect(now, keep);
  });

  test('an empty patch only bumps the version and updated_at', () async {
    final before = await f.services.waypoints.load(path);
    final w = await f.services.waypoints.update(path, const WaypointPatch());
    expect(w.userMetadata.version, before.userMetadata.version + 1);
    expect(w.userMetadata.updatedAtMs, 1760000060000);
    expect(w.location, before.location);
    expect(
      Map.of(w.userMetadata.entries)..remove('updated_at'),
      Map.of(before.userMetadata.entries)..remove('updated_at'),
    );
  });

  test('empty strings remove the keys', () async {
    final w = await f.services.waypoints.update(path, const WaypointPatch(comment: '', iconId: ''));
    expect(w.userMetadata.entries.containsKey('comment'), isFalse);
    expect(w.userMetadata.entries.containsKey('icon'), isFalse);
    expect(w.userMetadata.name, 'Bunker');
  });

  test('an invalid patch throws and leaves the file as it was', () async {
    final before = File(path).readAsBytesSync();
    await expectLater(f.services.waypoints.update(path, const WaypointPatch(longitude: 200)), throwsA(isA<ValidationException>()));
    expect(File(path).readAsBytesSync(), before);
  });

  test('delete is idempotent', () async {
    await f.services.waypoints.delete(path);
    expect(File(path).existsSync(), isFalse);
    await f.services.waypoints.delete(path);
  });

  test('move relocates the file without changing its content', () async {
    final before = await f.services.waypoints.load(path);
    final target = p.join(f.paths.landmarks, 'archive');
    final moved = await f.services.waypoints.move(path, target);
    expect(moved, p.join(target, p.basename(path)));
    expect(File(path).existsSync(), isFalse);
    expect(await f.services.waypoints.load(moved), before);
  });

  test('move with a new name cleans it and keeps .wpt', () async {
    final moved = await f.services.waypoints.move(path, f.paths.landmarks, newName: 'Old Bunker?');
    expect(p.basename(moved), 'old_bunker.wpt');
  });
}
