import 'dart:io';
import 'dart:typed_data';

import 'package:app/exceptions/storage_exception.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/repository/landmark_repository.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_permissions.dart';
import 'package:app/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late StoragePaths paths;
  late StorageService service;
  late LandmarkRepository repo;
  late DateTime now;

  final bunker = LandmarkFile.of(
    const WaypointObject(
      userMetadata: LandmarkMetadata(entries: {'name': 'Bunker', 'color': 0xFF00FF00}),
      location: LandmarkLocation(longitude: 30.5234, latitude: 50.4501),
    ),
  );

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('landmarks_');
    paths = StoragePaths.forRoot(tmp.path);
    service = StorageService(paths);
    now = DateTime.fromMillisecondsSinceEpoch(1760000000000);
    repo = LandmarkRepository(service, paths, clock: () => now);
    await service.ensureBaseFolders();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('save writes a readable file into landmarks and stamps the times', () async {
    final path = await repo.save(bunker);
    expect(path, p.join(paths.landmarks, 'bunker_1760000000000.wpt'));
    expect(File(path).existsSync(), isTrue);

    final loaded = await repo.load(path);
    expect(loaded.type, LandmarkType.waypoint);
    expect(loaded.content.userMetadata, bunker.content.userMetadata);
    expect((loaded.content as WaypointObject).location, (bunker.content as WaypointObject).location);
    expect(loaded.content.technicalMetadata.createdAtMs, 1760000000000);
    expect(loaded.content.technicalMetadata.updatedAtMs, 1760000000000);
  });

  test('save honours the directory and resolves name collisions', () async {
    final first = await repo.save(bunker, directory: paths.recordedTracks);
    final second = await repo.save(bunker, directory: paths.recordedTracks);
    expect(p.dirname(first), paths.recordedTracks);
    expect(p.basename(second), 'bunker_1760000000000_1.wpt');
  });

  test('save creates a missing directory', () async {
    final dir = p.join(paths.landmarks, 'new', 'deep');
    final path = await repo.save(bunker, directory: dir);
    expect(File(path).existsSync(), isTrue);
  });

  test('update bumps the version and updated_at, keeps created_at', () async {
    final path = await repo.save(bunker);
    final loaded = await repo.load(path);
    expect(loaded.content.technicalMetadata.version, 0);

    now = now.add(const Duration(minutes: 5));
    final renamed = WaypointObject(
      userMetadata: loaded.content.userMetadata.withEntries({'name': 'Bunker 2'}),
      technicalMetadata: loaded.content.technicalMetadata,
      location: (loaded.content as WaypointObject).location,
    );
    await repo.update(path, LandmarkFile.of(renamed));
    await repo.update(path, LandmarkFile.of(renamed));

    final after = await repo.load(path);
    expect(after.content.userMetadata.name, 'Bunker 2');
    expect(after.content.technicalMetadata.version, 2);
    expect(after.content.technicalMetadata.createdAtMs, 1760000000000);
    expect(after.content.technicalMetadata.updatedAtMs, 1760000300000);
  });

  test('update of a missing file fails', () async {
    expect(() => repo.update(p.join(paths.landmarks, 'nope.wpt'), bunker), throwsA(isA<StorageException>()));
  });

  test('delete removes the file and is idempotent', () async {
    final path = await repo.save(bunker);
    await repo.delete(path);
    expect(File(path).existsSync(), isFalse);
    await repo.delete(path);
  });

  test('move relocates the file, the source disappears', () async {
    final path = await repo.save(bunker);
    final moved = await repo.move(path, paths.importDefault);
    expect(moved, p.join(paths.importDefault, p.basename(path)));
    expect(File(path).existsSync(), isFalse);
    expect((await repo.load(moved)).content.userMetadata.name, 'Bunker');
  });

  test('move with a new name keeps the extension and avoids collisions', () async {
    final a = await repo.save(bunker);
    final b = await repo.save(bunker);
    final first = await repo.move(a, paths.importDefault, newName: 'renamed');
    final second = await repo.move(b, paths.importDefault, newName: 'renamed.wpt');
    expect(p.basename(first), 'renamed.wpt');
    expect(p.basename(second), 'renamed_1.wpt');
  });

  test('move of a missing file fails', () async {
    expect(() => repo.move(p.join(paths.landmarks, 'nope.wpt'), paths.importDefault), throwsA(isA<StorageException>()));
  });

  test('listIn returns only landmark files', () async {
    final saved = await repo.save(bunker);
    final track = await repo.save(LandmarkFile.of(const TrackObject(userMetadata: LandmarkMetadata(entries: {'name': 'Walk'}))));
    File(p.join(paths.landmarks, 'notes.txt')).writeAsStringSync('x');
    File(p.join(paths.landmarks, 'UPPER.SET')).writeAsBytesSync([0]);
    File(p.join(paths.landmarks, 'half.wpt.tmp.abcd1234')).writeAsBytesSync([0]);
    Directory(p.join(paths.landmarks, 'folder.wpt')).createSync();

    final listed = await repo.listIn(paths.landmarks);
    expect(listed, unorderedEquals([saved, track, p.join(paths.landmarks, 'UPPER.SET')]));
    expect(await repo.listIn(p.join(tmp.path, 'missing')), isEmpty);
  });

  group('atomic write', () {
    test('an interrupted write leaves no target and no temp file', () async {
      final failing = StorageService(paths, beforeCommit: (_) async => throw const FileSystemException('disk full'));
      final failingRepo = LandmarkRepository(failing, paths, clock: () => now);

      expect(() => failingRepo.save(bunker), throwsA(isA<StorageException>()));
      await Future<void>.delayed(Duration.zero);
      expect(Directory(paths.landmarks).listSync().whereType<File>(), isEmpty);
    });

    test('an interrupted overwrite keeps the old content', () async {
      final target = p.join(paths.landmarks, 'keep.bin');
      await service.atomicWriteBytes(target, Uint8List.fromList([1, 2, 3]));

      final failing = StorageService(paths, beforeCommit: (_) async => throw const FileSystemException('power loss'));
      await expectLater(failing.atomicWriteBytes(target, Uint8List.fromList([9, 9])), throwsA(isA<StorageException>()));

      expect(File(target).readAsBytesSync(), [1, 2, 3]);
      expect(Directory(paths.landmarks).listSync().map((e) => p.basename(e.path)), isNot(contains(contains('.tmp.'))));
    });
  });

  group('storage service', () {
    test('ensureBaseFolders creates every folder once', () async {
      final fresh = StorageService(StoragePaths.forRoot(p.join(tmp.path, 'fresh')));
      final created = await fresh.ensureBaseFolders();
      expect(created, hasLength(10));
      expect(created.every((d) => Directory(d).existsSync()), isTrue);
      expect(await fresh.ensureBaseFolders(), isEmpty);
    });

    test('checkWriteAccess grants a writable folder and leaves no probe', () async {
      final access = await service.checkWriteAccess(paths.landmarks);
      expect(access.granted, isTrue);
      expect(File(p.join(paths.landmarks, StorageService.writeCheckName)).existsSync(), isFalse);
    });

    test('checkWriteAccess denies a missing folder', () async {
      final access = await service.checkWriteAccess(p.join(tmp.path, 'missing'));
      expect(access.granted, isFalse);
      expect(access.reason, isNotNull);
    });

    test('readBytes of a missing file throws StorageException', () async {
      expect(() => service.readBytes(p.join(tmp.path, 'missing.wpt')), throwsA(isA<StorageException>()));
    });

    test('StoragePermissions verifies the app root without a runtime prompt', () async {
      final permissions = StoragePermissions(service, paths);
      expect(permissions.requiresRuntimePermission, isFalse);
      expect((await permissions.verify()).granted, isTrue);
    });
  });
}
