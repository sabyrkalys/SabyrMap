import 'package:app/icons/waypoint_icon_assignments_controller.dart';
import 'package:app/icons/waypoint_icon_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('build() starts empty', () {
    final container = ProviderContainer(
      overrides: [waypointIconStoreProvider.overrideWithValue(FakeWaypointIconStore())],
    );
    addTearDown(container.dispose);

    expect(container.read(waypointIconAssignmentsControllerProvider), isEmpty);
  });

  test('load() pulls every existing assignment from the store', () async {
    final store = FakeWaypointIconStore()..icons.addAll({'w1': 'volcano.svg'});
    final container = ProviderContainer(
      overrides: [waypointIconStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await container.read(waypointIconAssignmentsControllerProvider.notifier).load();

    expect(container.read(waypointIconAssignmentsControllerProvider), {'w1': 'volcano.svg'});
  });

  test('setIcon updates both the store and the in-memory state immediately', () async {
    final store = FakeWaypointIconStore();
    final container = ProviderContainer(
      overrides: [waypointIconStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await container.read(waypointIconAssignmentsControllerProvider.notifier).setIcon('w1', 'camp.png');

    expect(container.read(waypointIconAssignmentsControllerProvider), {'w1': 'camp.png'});
    expect(await store.iconFor('w1'), 'camp.png');
  });

  test('setIcon with null clears the assignment from state and store', () async {
    final store = FakeWaypointIconStore();
    final container = ProviderContainer(
      overrides: [waypointIconStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(waypointIconAssignmentsControllerProvider.notifier);
    await notifier.setIcon('w1', 'camp.png');

    await notifier.setIcon('w1', null);

    expect(container.read(waypointIconAssignmentsControllerProvider), isEmpty);
    expect(await store.iconFor('w1'), isNull);
  });
}
