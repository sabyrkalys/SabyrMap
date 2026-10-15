import 'package:app/landmarks/composite/edit_mode/edit_mode_controller.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../services/fixture.dart';

void main() {
  late ServicesFixture f;

  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.dispose());

  LandmarkLocation at(int i) => LandmarkLocation(longitude: 37 + i / 100, latitude: 48 + i / 100);

  for (final (type, ext) in [
    (LandmarkType.set, '.set'),
    (LandmarkType.route, '.rte'),
    (LandmarkType.track, '.trk'),
    (LandmarkType.area, '.are'),
  ]) {
    test('draws a new ${type.name}: points, undo/redo, minimum, saved and indexed', () async {
      final mode = f.services.editMode;
      mode.startNew(type, folder: f.paths.landmarks, metadata: const LandmarkMetadata(entries: {'name': 'Черновик'}));
      expect(mode.state.target!.isNew, isTrue);
      expect(mode.pointCount, 0);

      final need = EditModeController.minPoints[type]!;
      for (var i = 0; i < need - 1; i++) {
        expect(mode.addPoint(at(i)), isTrue);
      }
      if (need > 1) {
        expect(mode.canFinish, isFalse);
        await expectLater(mode.saveAndClose(), throwsStateError);
      }
      mode.addPoint(at(need - 1));
      mode.addPoint(at(need));
      mode.undo();
      expect(mode.pointCount, need);
      mode.redo();
      mode.undo();
      expect(mode.canFinish, isTrue);

      final path = (await mode.saveAndClose())!;
      expect(p.extension(path), ext);
      expect(mode.state.target, isNull);
      final item = f.services.index.byPath(path)!;
      expect((item.type, item.name), (type, 'Черновик'));

      final saved = (await f.services.repository.load(path)).content;
      final points = switch (saved) {
        SetObject(:final waypoints) || RouteObject(:final waypoints) => [for (final w in waypoints) w.location],
        TrackObject(:final segments) => segments.single.locations,
        AreaObject(:final polygons) => polygons.single.outline,
        _ => const <LandmarkLocation>[],
      };
      expect(points.map((l) => l.latitude), [for (var i = 0; i < need; i++) closeTo(at(i).latitude, 1e-6)]);
    });
  }

  test('a waypoint cannot be drawn; an empty track keeps no empty segment', () async {
    final mode = f.services.editMode;
    expect(() => mode.startNew(LandmarkType.waypoint), throwsArgumentError);
    expect(
      (await f.services.compositeCreation.createObject(const TrackObject(segments: [TrackSegment()]))).endsWith('.trk'),
      isTrue,
    );
  });
}
