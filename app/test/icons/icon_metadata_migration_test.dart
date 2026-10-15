import 'dart:io';

import 'package:app/icons/icon_metadata_migration.dart';
import 'package:app/icons/waypoint_icon_store.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../explorer/landmark_test_helpers.dart';

/// Хранилище значков в памяти — как защищённое, без платформы.
class MemoryIconStore implements WaypointIconStore {
  final Map<String, String> data = {};
  @override
  Future<String?> iconFor(String waypointId) async => data[waypointId];
  @override
  Future<void> setIcon(String waypointId, String? fileName) async =>
      fileName == null ? data.remove(waypointId) : data[waypointId] = fileName;
  @override
  Future<Map<String, String>> readAll() async => Map.of(data);
}

void main() {
  late Directory files;
  late LandmarkServices s;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Как на телефоне: files/mediafile — корень приложения.
    files = Directory.systemTemp.createTempSync('icon_migration_');
    s = await LandmarkServices.bootstrap(
      watchLandmarks: false,
      paths: StoragePaths.forRoot(p.join(files.path, StoragePaths.mediafileFolderName)),
      prefs: await SharedPreferences.getInstance(),
    );
  });
  tearDown(() => files.deleteSync(recursive: true));

  test('moves icons into the files: exact path and the pre-mediafile path with its subfolder', () async {
    final unsorted = p.join(s.paths.landmarks, 'Несортированные метки');
    final exact = await createWaypoint(s, 'Точно', unsorted);
    final moved = await createWaypoint(s, 'Перенесённая', unsorted);
    final oldPath = p.join(files.path, 'landmarks', 'Несортированные метки', p.basename(moved));
    final legacy = MemoryIconStore()
      ..data[exact] = 'tent.png'
      ..data[oldPath] = 'flag.png'
      ..data[p.join(files.path, 'landmarks', 'пропала.wpt')] = 'x.png';

    final orphans = await IconMetadataMigration.run(s, legacy);

    expect(s.index.byPath(exact)!.userIcon, 'tent.png');
    expect(s.index.byPath(moved)!.userIcon, 'flag.png');
    expect(orphans, [p.join(files.path, 'landmarks', 'пропала.wpt')]);
    expect(legacy.data.keys, orphans, reason: 'moved entries leave the store, orphans stay');

    legacy.data['ещё'] = 'y.png';
    expect(await IconMetadataMigration.run(s, legacy), isEmpty);
    expect(legacy.data, contains('ещё'), reason: 'runs once');
  });

  test('the file icon store keeps the icon through a rename', () async {
    final store = FileWaypointIconStore(s);
    final path = await createWaypoint(s, 'Палатка', s.paths.landmarks);
    await store.setIcon(path, 'tent.png');
    expect(await store.iconFor(path), 'tent.png');

    final renamed = await s.folders.renameFile(path, 'лагерь');
    expect(await store.readAll(), {renamed: 'tent.png'});

    await store.setIcon(renamed, null);
    expect(await store.iconFor(renamed), isNull);
  });
}
