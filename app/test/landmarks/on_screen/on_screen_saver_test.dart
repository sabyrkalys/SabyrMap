import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/on_screen/on_screen_saver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../explorer/landmark_test_helpers.dart';
import '../services/fixture.dart';

void main() {
  late ServicesFixture f;

  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.root.deleteSync(recursive: true));

  test('saves copies of every mark into one landmark file; a landmark file gives its objects', () async {
    final s = f.services;
    final byType = await createOneOfEach(s, f.paths.landmarks);
    final singles = [for (final e in byType.entries) if (e.key != LandmarkType.ldkFile) e.value];
    final first = await OnScreenSaver.saveAll(s, singles, name: 'Первый');
    final firstObjects = ((await s.repository.load(first)).content as LdkFileObject).objects;
    expect(firstObjects.map((o) => o.type).toSet(), {for (final path in singles) LandmarkType.fromExtension(p.extension(path))});

    final second = await OnScreenSaver.saveAll(s, [first, singles.first], name: 'Второй', comment: 'Весна');
    final file = (await s.repository.load(second)).content as LdkFileObject;
    expect(p.extension(second), '.ldk');
    expect(file.userMetadata.name, 'Второй');
    expect(file.userMetadata.entries[LandmarkMetadata.commentKey], 'Весна');
    expect(file.objects, hasLength(firstObjects.length + 1));
    expect(file.objects.whereType<LdkFileObject>(), isEmpty);
    // Исходные файлы на месте.
    for (final path in singles) {
      expect(await s.repository.load(path), isNotNull);
    }
  });
}
