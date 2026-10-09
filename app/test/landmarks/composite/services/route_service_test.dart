import 'package:app/landmarks/composite/drafts/route_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../services/fixture.dart';
import '../helpers.dart';

void main() {
  late ServicesFixture f;
  late String path;
  setUp(() async {
    f = await ServicesFixture.create();
    path = await f.services.compositeCreation.createRoute(RouteDraft(initialWaypoints: [loc(0, 0), loc(2, 2)]), loc(0, 0));
  });
  tearDown(() => f.dispose());

  test('insertWaypointAt(1) inserts in the middle', () async {
    final r = await f.services.routeService.insertWaypointAt(path, 1, wp(1, 1, 'mid'));
    expect([for (final w in r.waypoints) w.location.latitude], [0, 1, 2]);
    expect(r.waypoints[1].userMetadata.name, 'mid');
    expect(r.userMetadata.version, 1);
  });

  test('insert at 0 and at the end; past the end fails', () async {
    await f.services.routeService.insertWaypointAt(path, 0, wp(-1, -1));
    final r = await f.services.routeService.insertWaypointAt(path, 3, wp(3, 3));
    expect([for (final w in r.waypoints) w.location.latitude], [-1, 0, 2, 3]);
    await expectLater(f.services.routeService.insertWaypointAt(path, 9, wp(3, 3)), throwsRangeError);
  });

  test('the other operations work like a set', () async {
    await f.services.routeService.addWaypoint(path, wp(3, 3));
    await f.services.routeService.reorderWaypoints(path, 2, 0);
    final r = await f.services.routeService.removeWaypoint(path, 1);
    expect([for (final w in r.waypoints) w.location.latitude], [3, 2]);
    expect(r.userMetadata.version, 3);
  });
}
