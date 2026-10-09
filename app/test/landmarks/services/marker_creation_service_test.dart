import 'dart:io';

import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fixture.dart';

void main() {
  late ServicesFixture f;
  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.dispose());

  const draft = MarkerDraft(
    type: LandmarkType.waypoint,
    longitude: 30.5234,
    latitude: 50.4501,
    name: '  Bunker  ',
    comment: 'вход с севера',
    description: '',
    colorValue: 0xFF00FF00,
    iconId: 'tourism/tent',
  );

  test('a valid draft is saved into the default folder', () async {
    final path = await f.services.creation.create(draft);
    expect(p.dirname(path), f.paths.importDefault);
    expect(p.basename(path), 'bunker_1760000000000.wpt');
    expect(File(path).existsSync(), isTrue);
  });

  test('the saved waypoint carries the draft and fresh timestamps', () async {
    final path = await f.services.creation.create(draft);
    final waypoint = await f.services.waypoints.load(path);
    final meta = waypoint.userMetadata;
    expect(meta.version, 0);
    expect(meta.name, 'Bunker');
    expect(meta.comment, 'вход с севера');
    expect(meta.entries.containsKey('description'), isFalse);
    expect(meta.colorValue, 0xFF00FF00);
    expect(meta.iconId, 'tourism/tent');
    expect(meta.createdAtMs, 1760000000000);
    expect(meta.updatedAtMs, 1760000000000);
    expect(waypoint.location.longitude, closeTo(30.5234, 1e-7));
    expect(waypoint.location.latitude, closeTo(50.4501, 1e-7));
  });

  test('a waypoint without a name is saved as untitled', () async {
    final path = await f.services.creation.create(draft.copyWith(name: '   '));
    expect(p.basename(path), startsWith('untitled_'));
    expect((await f.services.waypoints.load(path)).userMetadata.name, isNull);
  });

  test('targetFolder wins over the default', () async {
    final target = p.join(f.paths.landmarks, 'trip');
    final path = await f.services.creation.create(draft.copyWith(targetFolder: target));
    expect(p.dirname(path), target);
  });

  test('the default folder from settings is used', () async {
    await f.services.folders.ensureFolder(f.paths.recordedTracks);
    await f.services.folders.setDefaultFolder(f.paths.recordedTracks);
    final path = await f.services.creation.create(draft);
    expect(p.dirname(path), f.paths.recordedTracks);
  });

  test('an invalid draft throws and writes nothing', () async {
    await expectLater(
      f.services.creation.create(draft.copyWith(latitude: 95)),
      throwsA(isA<ValidationException>().having((e) => e.errors.single, 'error', contains('latitude'))),
    );
    await expectLater(f.services.creation.create(draft.copyWith(type: LandmarkType.set)), throwsA(isA<ValidationException>()));
    final files = Directory(f.paths.landmarks).listSync(recursive: true).whereType<File>();
    expect(files, isEmpty);
  });
}
