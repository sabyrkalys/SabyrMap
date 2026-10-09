import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/navigation/proximity/proximity_alert.dart';
import 'package:app/navigation/proximity/proximity_alert_store.dart';
import 'package:app/navigation/proximity/proximity_zone.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes.dart';

void main() {
  late AppSettings settings;
  late ProximityAlertStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    store = ProximityAlertStore(settings);
  });

  final a = ProximityAlert(id: 'a', name: 'Camp', center: loc(50.45, 30.52), radiusMeters: 200, repeatNotifications: true);
  final b = ProximityAlert(id: 'b', name: 'Post', center: loc(50.5, 30.6), radiusMeters: 50, setAsTarget: true, isActive: false);

  test('an empty store gives an empty list', () async {
    expect(await store.load('ws'), isEmpty);
    expect(await store.loadZones('ws'), isEmpty);
  });

  test('save and load round-trip under the workspace key', () async {
    await store.save('ws', [a, b]);
    expect(await store.load('ws'), [a, b]);
    expect(await store.load('other'), isEmpty);
    expect(settings.getString('navigation.proximity.ws'), startsWith('['));
  });

  test('add, update, remove', () async {
    await store.add('ws', a);
    await store.add('ws', b);
    await store.update('ws', a.copyWith(name: 'Lake', radiusMeters: 300));
    var loaded = await store.load('ws');
    expect(loaded.map((x) => x.name), ['Lake', 'Post']);
    expect(loaded.first.radiusMeters, 300);
    await store.remove('ws', 'a');
    loaded = await store.load('ws');
    expect(loaded, [b]);
  });

  test('zones round-trip; a broken record reads as empty', () async {
    await store.saveZones('ws', {'a': ProximityZone.inner, 'b': ProximityZone.outside});
    expect(await store.loadZones('ws'), {'a': ProximityZone.inner, 'b': ProximityZone.outside});
    await settings.setString('navigation.proximity.bad', '{nope');
    expect(await store.load('bad'), isEmpty);
  });

  test('created alerts get a UUID', () {
    final x = ProximityAlert.create(name: 'x', center: loc(0, 0), radiusMeters: 10);
    expect(x.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(x.isActive, isTrue);
  });
}
