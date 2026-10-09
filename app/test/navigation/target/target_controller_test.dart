import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/navigation/target/target_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../landmarks/services/fixture.dart';
import '../fakes.dart';

void main() {
  late ServicesFixture f;
  late FakePositionSource position;
  late TargetController c;
  setUp(() async {
    f = await ServicesFixture.create();
    position = FakePositionSource();
    c = TargetController(position, waypoints: f.services.waypoints);
  });
  tearDown(() => f.dispose());

  test('setTarget from a known source: active, info filled', () async {
    c.updateSource(loc(0, 0));
    expect(c.state.isActive, isFalse);
    await c.setTarget(loc(0, 1, ele: 50));
    expect(c.state.isActive, isTrue);
    expect(c.state.info!.distanceMeters, closeTo(111195, 200));
    expect(c.state.info!.azimuthDeg, closeTo(90, 1e-9));
  });

  test('without a source the device position is used, with ETA', () async {
    position.current = at(0, 0, speed: 10);
    await c.setTarget(loc(0, 0.01));
    expect(c.state.source, loc(0, 0));
    expect(c.state.info!.etaSeconds, (c.state.info!.distanceMeters / 10).round());
  });

  test('without any source the target is set without info', () async {
    await c.setTarget(loc(1, 1));
    expect(c.state.isActive, isTrue);
    expect(c.state.info, isNull);
  });

  test('removeTarget empties the state, keeps display options', () async {
    c.setDisplayLine(false);
    c.updateSource(loc(0, 0));
    await c.setTarget(loc(1, 1));
    await c.removeTarget();
    expect(c.state.isActive, isFalse);
    expect(c.state.info, isNull);
    expect(c.state.source, isNull);
    expect(c.state.displayLine, isFalse);
  });

  test('updateSource recomputes distance and azimuth', () async {
    c.updateSource(loc(0, 0));
    await c.setTarget(loc(0, 1));
    c.updateSource(loc(1, 1));
    expect(c.state.info!.azimuthDeg, closeTo(180, 1e-9));
    expect(c.state.info!.distanceMeters, closeTo(111195, 200));
  });

  test('display options change the state and notify', () {
    var notified = 0;
    c.addListener(() => notified++);
    c.setDisplayLine(false);
    c.setDisplayInfoBox(false);
    c.setDisplayInfoBox(false);
    expect((c.state.displayLine, c.state.displayInfoBox), (false, false));
    expect(notified, 2);
  });

  test('refresh follows the device; jumpToTarget returns the target', () async {
    c.updateSource(loc(0, 0));
    await c.setTarget(loc(0, 1));
    position.current = at(0, 0.5);
    await c.refresh();
    expect(c.state.info!.distanceMeters, closeTo(111195 / 2, 100));
    expect(await c.jumpToTarget(), loc(0, 1));
  });

  test('operations without a target change nothing', () async {
    var notified = 0;
    c.addListener(() => notified++);
    await c.removeTarget();
    await c.refresh();
    c.updateSource(loc(0, 0));
    expect(await c.jumpToTarget(), isNull);
    expect(notified, 0);
  });

  test('setTargetFromWaypoint reads the file', () async {
    final path = await f.services.creation.create(
      const MarkerDraft(type: LandmarkType.waypoint, longitude: 30.52, latitude: 50.45, name: 'Bunker'),
    );
    await c.setTargetFromWaypoint(path);
    expect(c.state.target!.latitude, closeTo(50.45, 1e-7));
  });
}
