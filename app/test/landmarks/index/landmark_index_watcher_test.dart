import 'dart:io';

import 'package:app/landmarks/explorer/listing/landmark_item_reader.dart';
import 'package:app/landmarks/index/landmark_index.dart';
import 'package:app/landmarks/index/landmark_index_watcher.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/serialization/landmark_codec.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LandmarkIndex index;
  late LandmarkIndexWatcher watcher;

  List<int> waypoint(String name) => LandmarkCodec.encode(
    LandmarkFile.of(
      WaypointObject(
        location: const LandmarkLocation(longitude: 37, latitude: 48),
        userMetadata: LandmarkMetadata(entries: {'name': name}),
      ),
    ),
  );

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 400));

  setUp(() async {
    root = Directory.systemTemp.createTempSync('landmark_watch_');
    index = LandmarkIndex(root.path, LandmarkItemReader(StorageService(StoragePaths.forRoot(root.path))));
    await index.rebuild();
    watcher = LandmarkIndexWatcher(index, debounce: const Duration(milliseconds: 100))..start();
    await watcher.ready;
  });

  tearDown(() async {
    await watcher.stop();
    root.deleteSync(recursive: true);
  });

  test('a file created, changed and deleted from outside reaches the index', () async {
    final path = p.join(root.path, 'внешняя.wpt');
    File(path).writeAsBytesSync(waypoint('Снаружи'));
    await settle();
    expect(index.byPath(path)!.name, 'Снаружи');

    File(path).writeAsBytesSync(waypoint('Изменена'));
    await settle();
    expect(index.byPath(path)!.name, 'Изменена');

    File(path).deleteSync();
    await settle();
    expect(index.byPath(path), isNull);
  });

  test('temporary files of atomic writes are ignored', () async {
    var notified = 0;
    index.addListener(() => notified++);
    File(p.join(root.path, 'a.wpt.tmp.123')).writeAsBytesSync(waypoint('Временный'));
    await settle();
    expect(notified, 0);
    expect(index.items, isEmpty);
  });
}
