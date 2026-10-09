import 'dart:io';

import 'package:app/intents/intent_kind.dart';
import 'package:app/intents/intent_payload.dart';
import 'package:app/intents/tracker_intent.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../landmarks/services/fixture.dart';

class RecordingTracker extends TrackerService {
  final List<TrackerAction> actions = [];

  @override
  Future<void> handle(TrackerIntent intent) async => actions.add(intent.action);
}

void main() {
  late ServicesFixture f;
  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.dispose());
  const kyiv = LandmarkLocation(latitude: 50.45, longitude: 30.52);

  test('displayLocation sets the target', () async {
    await f.services.intentDispatcher.dispatch(
      const IntentPayload(kind: IntentKind.displayLocation, location: kyiv, moveTo: true),
    );
    expect(f.services.targetController.state.target, kyiv);
  });

  test('displayLocation without a location does nothing', () async {
    await f.services.intentDispatcher.dispatch(const IntentPayload(kind: IntentKind.displayLocation));
    expect(f.services.targetController.state.isActive, isFalse);
  });

  test('fastWaypoint creates a waypoint with the name', () async {
    final dispatcher = f.services.intentDispatcher;
    await dispatcher.dispatch(
      const IntentPayload(kind: IntentKind.fastWaypoint, location: kyiv, name: 'Bunker', iconId: 'flag'),
    );
    final path = dispatcher.lastCreatedPath!;
    expect(File(path).existsSync(), isTrue);
    expect(p.dirname(path), f.paths.importDefault);
    final wp = await f.services.waypoints.load(path);
    expect(wp.userMetadata.name, 'Bunker');
    expect(wp.userMetadata.iconId, 'flag');
  });

  test('fastWaypoint goes to the current explorer folder when set', () async {
    await f.services.folders.setCurrentFolder(f.paths.recordedTracks);
    await f.services.intentDispatcher.dispatch(const IntentPayload(kind: IntentKind.fastWaypoint, location: kyiv));
    expect(p.dirname(f.services.intentDispatcher.lastCreatedPath!), f.paths.recordedTracks);
  });

  test('tracker, app stop and unknown do not fail', () async {
    for (final kind in [
      IntentKind.trackerStart,
      IntentKind.trackerStop,
      IntentKind.trackerAddWaypoint,
      IntentKind.appStop,
      IntentKind.unknown,
    ]) {
      await f.services.intentDispatcher.dispatch(IntentPayload(kind: kind));
    }
    expect(f.services.targetController.state.isActive, isFalse);
  });

  test('tracker requests reach the tracker service', () async {
    final tracker = RecordingTracker();
    final services = await ServicesFixture.create(tracker: tracker);
    addTearDown(services.dispose);
    await services.services.intentDispatcher.dispatch(const IntentPayload(kind: IntentKind.trackerStart));
    await services.services.intentDispatcher.dispatch(const IntentPayload(kind: IntentKind.trackerAddWaypoint));
    expect(tracker.actions, [TrackerAction.start, TrackerAction.addWaypoint]);
  });
}

