import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/navigation/proximity/proximity_alert.dart';
import 'package:app/navigation/proximity/proximity_alert_controller.dart';
import 'package:app/navigation/proximity/proximity_alert_signal.dart';
import 'package:app/navigation/proximity/proximity_alert_store.dart';
import 'package:app/navigation/proximity/proximity_zone.dart';
import 'package:app/navigation/signals/signal_kind.dart';
import 'package:app/navigation/target/target_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../landmarks/services/fixture.dart';
import '../fakes.dart';

void main() {
  // 0.0009° широты ≈ 100 м.
  const m100 = 0.00089932;
  late ServicesFixture f;
  late ProximityAlertStore store;
  late FakePositionSource position;
  late RecordingSignaler signaler;
  late ProximityAlertSignalEmitter emitter;
  late TargetController target;
  late ProximityAlertController c;

  final alert = ProximityAlert(id: 'camp', name: 'Camp', center: loc(0, 0), radiusMeters: 400, setAsTarget: true);

  setUp(() async {
    f = await ServicesFixture.create();
    store = ProximityAlertStore(AppSettings(await SharedPreferences.getInstance()));
    position = FakePositionSource();
    signaler = RecordingSignaler();
    emitter = ProximityAlertSignalEmitter(signaler, interval: const Duration(milliseconds: 20));
    target = TargetController(position, waypoints: f.services.waypoints);
    c = ProximityAlertController(store, position, signaler, target, emitter: emitter);
    await c.load('ws');
  });
  tearDown(() async {
    await emitter.stopAll();
    f.dispose();
  });

  test('add puts the alert into the list and the store', () async {
    await c.add(alert);
    expect(c.alerts, [alert]);
    expect(await store.load('ws'), [alert]);
  });

  test('outside → outer gives goodWay1, then deeper zones', () async {
    await c.add(alert);
    await c.updatePosition(at(10 * m100, 0));
    expect(c.state.currentZones['camp'], ProximityZone.outside);
    expect(signaler.played, isEmpty);
    await c.updatePosition(at(3 * m100, 0));
    expect(c.state.currentZones['camp'], ProximityZone.outer);
    expect(signaler.played, [SignalKind.goodWay1]);
    await c.updatePosition(at(1.5 * m100, 0));
    expect(signaler.played.last, SignalKind.goodWay2);
  });

  test('inner sets the centre as target', () async {
    await c.add(alert);
    await c.updatePosition(at(3 * m100, 0));
    await c.updatePosition(at(1.5 * m100, 0));
    expect(target.state.isActive, isFalse);
    await c.updatePosition(at(0.5 * m100, 0));
    expect(signaler.played.last, SignalKind.goodWay3);
    expect(target.state.target, alert.center);
  });

  test('leaving gives wrongWay; the radius exit sounds once', () async {
    await c.add(alert.copyWith(repeatNotifications: true));
    await c.updatePosition(at(3 * m100, 0));
    await c.updatePosition(at(10 * m100, 0));
    expect(signaler.played, [SignalKind.goodWay1, SignalKind.wrongWay2]);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(signaler.played, hasLength(2));
  });

  test('repeatNotifications repeats until the next transition', () async {
    await c.add(alert.copyWith(repeatNotifications: true));
    await c.updatePosition(at(3 * m100, 0));
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(signaler.played.where((s) => s == SignalKind.goodWay1).length, greaterThan(1));
  });

  test('remove drops the alert from the list and the zones', () async {
    await c.add(alert);
    await c.updatePosition(at(3 * m100, 0));
    await c.remove('camp');
    expect(c.alerts, isEmpty);
    expect(c.state.currentZones, isEmpty);
    expect(await store.load('ws'), isEmpty);
  });

  test('deactivating drops it from the zones and stops checking', () async {
    await c.add(alert);
    await c.updatePosition(at(3 * m100, 0));
    await c.update(alert.copyWith(isActive: false));
    expect(c.state.currentZones, isEmpty);
    await c.updatePosition(at(1.5 * m100, 0));
    expect(c.state.currentZones, isEmpty);
    expect(signaler.played, [SignalKind.goodWay1]);
  });

  test('load restores the list and zones from the store', () async {
    await c.add(alert);
    await c.updatePosition(at(3 * m100, 0));
    final again = ProximityAlertController(store, position, signaler, target, emitter: emitter);
    await again.load('ws');
    expect(again.alerts, [alert]);
    expect(again.state.currentZones, {'camp': ProximityZone.outer});
    await again.updatePosition(at(3 * m100, 0));
    expect(signaler.played, [SignalKind.goodWay1]);
  });

  test('add checks the alert against the current position', () async {
    position.current = at(3 * m100, 0);
    await c.add(alert);
    expect(c.state.currentZones['camp'], ProximityZone.outer);
  });
}
