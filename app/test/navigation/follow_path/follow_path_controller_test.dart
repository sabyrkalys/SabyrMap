import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/navigation/follow_path/follow_path_controller.dart';
import 'package:app/navigation/follow_path/follow_path_signal.dart';
import 'package:app/navigation/signals/signal_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../landmarks/services/fixture.dart';
import '../fakes.dart';

void main() {
  const step = 0.0044966;
  late ServicesFixture f;
  late FakePositionSource position;
  late RecordingSignaler signaler;
  late FollowPathSignalEmitter emitter;
  late FollowPathController c;
  late String path;
  setUp(() async {
    f = await ServicesFixture.create();
    position = FakePositionSource();
    signaler = RecordingSignaler();
    emitter = FollowPathSignalEmitter(signaler, interval: const Duration(milliseconds: 20));
    c = FollowPathController(f.services.trackService, position, signaler, emitter);
    path = await f.services.compositeCreation.createTrack(
      TrackDraft(initialLocations: [loc(0, 0), loc(step, 0), loc(2 * step, 0), loc(3 * step, 0)]),
      loc(0, 0),
    );
  });
  tearDown(() async {
    await emitter.stop();
    f.dispose();
  });

  test('start loads the track: active, dashboard from the start', () async {
    await c.start(path, autoTargetDistanceMeters: 400);
    expect(c.state.isActive, isTrue);
    expect(c.state.trackPath, path);
    expect(c.state.dashboard!.remainingDistanceMeters, closeTo(1500, 2));
    expect(c.state.dashboard!.distanceToTrackMeters, isNull);
    expect(c.autoTarget, loc(step, 0));
  });

  test('start of a missing or empty track gives an error, not active', () async {
    await c.start('${f.root.path}/none.trk');
    expect(c.state.isActive, isFalse);
    expect(c.state.errorMessage, isNotNull);
    final empty = await f.services.compositeCreation.createTrack(const TrackDraft(), loc(0, 0));
    await c.start(empty);
    expect(c.state.errorMessage, contains('no points'));
  });

  test('updatePosition moves along and updates the dashboard and auto target', () async {
    await c.start(path, autoTargetDistanceMeters: 400);
    await c.updatePosition(at(step * 1.05, 0.0001, speed: 1));
    expect(c.state.currentPointIndex, 1);
    expect(c.state.dashboard!.remainingDistanceMeters, closeTo(1000, 2));
    expect(c.state.dashboard!.etaSeconds, closeTo(1000, 2));
    expect(c.state.dashboard!.distanceToTrackMeters, lessThan(50));
    expect(c.autoTarget, loc(2 * step, 0));
    expect(c.state.deviationSignaled, isFalse);
  });

  test('going off the track signals, coming back is quiet', () async {
    await c.start(path);
    await c.updatePosition(at(step, 0.0001));
    await c.updatePosition(at(step, 0.001));
    expect(c.state.deviationSignaled, isTrue);
    expect(signaler.played, [SignalKind.wrongWay2]);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(signaler.played.length, greaterThan(1));
    await c.updatePosition(at(step, 0.0006));
    expect(signaler.played.last, SignalKind.goodWay1);
    await c.updatePosition(at(step, 0.0001));
    expect(c.state.deviationSignaled, isFalse);
    final count = signaler.played.length;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(signaler.played.length, count);
  });

  test('reverseOrder turns the track around', () async {
    await c.start(path, reverseOrder: true);
    expect(c.state.track!.segments.single.locations.first, loc(3 * step, 0));
    c.setReverseOrder(false);
    expect(c.state.track!.segments.single.locations.first, loc(0, 0));
    expect(c.state.reverseOrder, isFalse);
  });

  test('loop goes back to the start at the end', () async {
    await c.start(path, loop: true);
    await c.updatePosition(at(3 * step, 0));
    expect(c.state.isActive, isTrue);
    expect((c.state.currentSegmentIndex, c.state.currentPointIndex), (0, 0));
    expect(c.state.dashboard!.remainingDistanceMeters, closeTo(1500, 2));
  });

  test('without loop the end stops following', () async {
    await c.start(path);
    await c.updatePosition(at(3 * step, 0));
    expect(c.state.isActive, isFalse);
  });

  test('stop clears the state and silences', () async {
    await c.start(path, autoTargetDistanceMeters: 100);
    await c.stop();
    expect(c.state.isActive, isFalse);
    expect(c.state.dashboard, isNull);
    expect(c.autoTarget, isNull);
    expect(signaler.stops, greaterThan(0));
  });

  test('settings change the state', () async {
    await c.start(path);
    c.setLoop(true);
    c.setDeviationThreshold(20);
    c.setAutoTargetDistanceMeters(0);
    expect(c.state.loop, isTrue);
    expect(c.state.deviationThresholdMeters, 20);
    expect(c.autoTarget, loc(0, 0));
    c.setAutoTargetDistanceMeters(null);
    expect(c.autoTarget, isNull);
  });

  test('a known device position is used at start', () async {
    position.current = at(step, 0.0001);
    await c.start(path);
    expect(c.state.currentPointIndex, 1);
    expect(c.state.dashboard!.distanceToTrackMeters, isNotNull);
  });
}
