import 'package:app/landmarks/composite/drafts/set_draft.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../services/fixture.dart';
import '../helpers.dart';

void main() {
  late ServicesFixture f;
  late String path;
  setUp(() async {
    f = await ServicesFixture.create();
    path = await f.services.compositeCreation.createSet(
      SetDraft(name: 'S', initialWaypoints: [loc(0, 0), loc(1, 1), loc(2, 2)]),
      loc(0, 0),
    );
    f.now = f.now.add(const Duration(minutes: 1));
  });
  tearDown(() => f.dispose());

  List<double> lats(SetObject s) => [for (final w in s.waypoints) w.location.latitude];

  test('addWaypoint: count +1, version +1, updated_at', () async {
    final s = await f.services.setService.addWaypoint(path, wp(3, 3));
    expect(s.waypoints, hasLength(4));
    expect(s.userMetadata.version, 1);
    expect(s.userMetadata.updatedAtMs, 1760000060000);
    expect(s.userMetadata.createdAtMs, 1760000000000);
  });

  test('removeWaypoint(0) keeps the order of the rest', () async {
    expect(lats(await f.services.setService.removeWaypoint(path, 0)), [1, 2]);
  });

  test('reorderWaypoints(0, 2)', () async {
    expect(lats(await f.services.setService.reorderWaypoints(path, 0, 2)), [1, 2, 0]);
  });

  test('updateWaypointAt', () async {
    final s = await f.services.setService.updateWaypointAt(path, 1, wp(9, 9, 'nine'));
    expect(s.waypoints[1].userMetadata.name, 'nine');
  });

  test('updateMetadata: version +1, name changed; length is recomputed', () async {
    final s = await f.services.setService.updateMetadata(path, const MetadataPatch(set: {'name': 'Renamed'}));
    expect(s.userMetadata.version, 1);
    expect(s.userMetadata.name, 'Renamed');
    final shorter = await f.services.setService.removeWaypoint(path, 2);
    expect(shorter.userMetadata.entries['length_m'], lessThan(s.userMetadata.entries['length_m'] as double));
    expect(shorter.userMetadata.version, 2);
  });

  test('a bad index or coordinates change nothing', () async {
    await expectLater(f.services.setService.removeWaypoint(path, 5), throwsRangeError);
    await expectLater(f.services.setService.addWaypoint(path, wp(95, 0)), throwsA(isA<ValidationException>()));
    expect((await f.services.setService.load(path)).userMetadata.version, 0);
  });

  test('load of another type fails; delete removes the file', () async {
    final track = await f.services.repository.save(LandmarkFile.of(const TrackObject()));
    await expectLater(f.services.setService.load(track), throwsA(anything));
    await f.services.setService.delete(path);
    await f.services.setService.delete(path);
    await expectLater(f.services.setService.load(path), throwsA(anything));
  });
}
