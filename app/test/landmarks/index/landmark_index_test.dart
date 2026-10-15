import 'dart:io';

import 'package:app/landmarks/explorer/listing/landmark_item_reader.dart';
import 'package:app/landmarks/index/landmark_index.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/on_screen/on_screen_saver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../explorer/landmark_test_helpers.dart';
import '../services/fixture.dart';

void main() {
  late ServicesFixture f;
  late LandmarkIndex index;
  var notified = 0;

  setUp(() async {
    f = await ServicesFixture.create();
    index = LandmarkIndex(f.paths.landmarks, LandmarkItemReader(f.services.storage))
      ..addListener(() => notified++);
    notified = 0;
  });
  tearDown(() => f.dispose());

  test('rebuild finds every type, folders included, and the objects inside a landmark file', () async {
    final byType = await createOneOfEach(f.services, f.paths.landmarks);
    final sub = p.join(f.paths.landmarks, 'Поход');
    final inSub = await createWaypoint(f.services, 'Вершина', sub);
    final ldk = await OnScreenSaver.saveAll(f.services, [byType[LandmarkType.waypoint]!, inSub], name: 'Архив');
    File(p.join(f.paths.landmarks, 'readme.txt')).writeAsStringSync('не метка');

    await index.rebuild();

    expect(index.isReady, isTrue);
    expect(notified, 1);
    expect(index.byType(LandmarkType.waypoint, nested: false), hasLength(2));
    expect(index.byType(LandmarkType.waypoint), hasLength(4));
    expect(index.byType(LandmarkType.track), hasLength(1));
    expect(index.byPath(inSub)!.name, 'Вершина');
    expect(index.inFolder(f.paths.landmarks).map((i) => i.path), isNot(contains(inSub)));
    expect(index.inFolder(f.paths.landmarks, recursive: true).map((i) => i.path), contains(inSub));
    expect(index.inFolder(sub).single.path, inSub);
    final nested = index.nestedIn(ldk);
    expect(nested.map((i) => i.name), ['Перевал', 'Вершина']);
    expect(nested.first.isNested, isTrue);
    expect(nested.first.filePath, ldk);
    expect(nested.first.latitude, closeTo(42.87, 1e-6));
  });

  test('refresh picks up a new, changed and deleted file and a whole folder', () async {
    await index.rebuild();
    final path = await createWaypoint(f.services, 'Старт', f.paths.landmarks);
    await index.refresh([path]);
    expect(index.byPath(path)!.name, 'Старт');

    final file = await f.services.repository.load(path);
    await f.services.repository.update(
      path,
      file.withContent(file.content.withUserMetadata(file.content.userMetadata.withEntries({'name': 'Финиш'}))),
    );
    await index.refresh([path]);
    expect(index.byPath(path)!.name, 'Финиш');

    final sub = p.join(f.paths.landmarks, 'Лагерь');
    final a = await createWaypoint(f.services, 'А', sub);
    await index.refresh([sub]);
    expect(index.byPath(a), isNotNull);

    Directory(sub).deleteSync(recursive: true);
    File(path).deleteSync();
    await index.refresh([sub, path]);
    expect(index.items, isEmpty);
  });

  test('a rewritten landmark file replaces its objects; paths outside the folder are ignored', () async {
    await index.rebuild();
    final a = await createWaypoint(f.services, 'А', f.paths.landmarks);
    final b = await createWaypoint(f.services, 'Б', f.paths.landmarks);
    final ldk = await OnScreenSaver.saveAll(f.services, [a, b], name: 'Архив');
    await index.refresh([ldk]);
    expect(index.nestedIn(ldk), hasLength(2));

    final file = await f.services.repository.load(ldk);
    await f.services.repository.update(
      ldk,
      LandmarkFile.of(LdkFileObject(userMetadata: file.content.userMetadata, objects: [(file.content as LdkFileObject).objects.first])),
    );
    await index.refresh([ldk]);
    expect(index.nestedIn(ldk).map((i) => i.name), ['А']);

    final before = notified;
    await index.refresh([p.join(f.root.path, 'elsewhere.wpt')]);
    expect(notified, before);
  });

  test('every write through the services reaches the services index without a manual refresh', () async {
    final s = f.services;
    final index = s.index;
    final path = await createWaypoint(s, 'Старт', f.paths.landmarks);
    expect(index.byPath(path)!.name, 'Старт');

    final renamed = await s.folders.renameFile(path, 'финиш');
    expect(index.byPath(path), isNull);
    expect(index.byPath(renamed), isNotNull);

    final sub = p.join(f.paths.landmarks, 'Лагерь');
    await s.folders.ensureFolder(sub);
    final moved = await s.repository.move(renamed, sub);
    expect(index.inFolder(sub).single.path, moved);

    final other = p.join(f.paths.landmarks, 'База');
    await s.folders.rename(sub, other);
    expect(index.inFolder(other).single.name, 'Старт');
    expect(index.inFolder(sub), isEmpty);

    await s.folders.deleteRecursive(other);
    expect(index.items, isEmpty);
  });
}
