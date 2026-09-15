import 'package:app/icons/waypoint_icon_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('WaypointIconStore contract (via FakeWaypointIconStore)', () {
    late WaypointIconStore store;

    setUp(() => store = FakeWaypointIconStore());

    test('iconFor returns null when nothing is set', () async {
      expect(await store.iconFor('w1'), isNull);
    });

    test('setIcon then iconFor round-trips', () async {
      await store.setIcon('w1', 'volcano.svg');
      expect(await store.iconFor('w1'), 'volcano.svg');
    });

    test('setIcon with null clears a previous assignment', () async {
      await store.setIcon('w1', 'volcano.svg');
      await store.setIcon('w1', null);
      expect(await store.iconFor('w1'), isNull);
    });

    test('readAll returns every assignment', () async {
      await store.setIcon('w1', 'volcano.svg');
      await store.setIcon('w2', 'camp.png');
      expect(await store.readAll(), {'w1': 'volcano.svg', 'w2': 'camp.png'});
    });
  });
}
