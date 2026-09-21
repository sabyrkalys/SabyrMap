import 'package:app/icons/icon_library_scanner.dart';
import 'package:app/icons/waypoint_icon_assignments_controller.dart';
import 'package:app/icons/waypoint_icon_store.dart';
import 'package:app/waypoints/waypoint_actions.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../icons/fakes.dart';
import 'fakes.dart';

Waypoint _waypoint() => Waypoint(
      id: 'w1',
      orgId: 'o1',
      ownerId: 'u1',
      name: 'Summit',
      type: 'generic',
      note: null,
      lat: 1.0,
      lng: 2.0,
      canEdit: true,
      createdAt: DateTime.utc(2026, 8, 22),
    );

void main() {
  testWidgets('editing a waypoint and picking an icon persists the assignment', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('camp.png').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    final repo = FakeWaypointsRepository()..updateResult = _waypoint();
    final iconStore = FakeWaypointIconStore();
    final container = ProviderContainer(
      overrides: [
        waypointsRepositoryProvider.overrideWithValue(repo),
        waypointIconStoreProvider.overrideWithValue(iconStore),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => editWaypoint(context, ref, _waypoint(), iconScanner: scanner),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('waypoint_icon_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_tile_camp.png')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Summit');
    await tester.pump();
    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await tester.pumpAndSettle();

    expect(await iconStore.iconFor('w1'), 'camp.png');
    expect(container.read(waypointIconAssignmentsControllerProvider), {'w1': 'camp.png'});
  });

  testWidgets('editWaypoint: a setIcon failure does not propagate and does not undo the server update', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('camp.png').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    final updated = Waypoint(
      id: 'w1',
      orgId: 'o1',
      ownerId: 'u1',
      name: 'Renamed',
      type: 'generic',
      note: null,
      lat: 1.0,
      lng: 2.0,
      canEdit: true,
      createdAt: DateTime.utc(2026, 8, 22),
    );
    final repo = FakeWaypointsRepository(initial: [_waypoint()])..updateResult = updated;
    final iconStore = FakeWaypointIconStore()..setIconError = Exception('local storage boom');
    final container = ProviderContainer(
      overrides: [
        waypointsRepositoryProvider.overrideWithValue(repo),
        waypointIconStoreProvider.overrideWithValue(iconStore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(waypointsControllerProvider.notifier).loadWaypoints();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => editWaypoint(context, ref, _waypoint(), iconScanner: scanner),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Renamed');
    await tester.pump();
    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await tester.pumpAndSettle();

    // No unhandled exception should have propagated out of editWaypoint.
    expect(tester.takeException(), isNull);
    // The server-side update already took effect.
    expect(container.read(waypointsControllerProvider).single.name, 'Renamed');
    // No WaypointException SnackBar was shown for this soft failure.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('deleteWaypoint: a setIcon failure does not propagate and does not undo the server delete', (tester) async {
    final repo = FakeWaypointsRepository(initial: [_waypoint()]);
    final iconStore = FakeWaypointIconStore()..setIconError = Exception('local storage boom');
    final container = ProviderContainer(
      overrides: [
        waypointsRepositoryProvider.overrideWithValue(repo),
        waypointIconStoreProvider.overrideWithValue(iconStore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(waypointsControllerProvider.notifier).loadWaypoints();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => deleteWaypoint(context, ref, _waypoint()),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    // No unhandled exception should have propagated out of deleteWaypoint.
    expect(tester.takeException(), isNull);
    // The server-side delete already took effect.
    expect(container.read(waypointsControllerProvider), isEmpty);
    // No WaypointException SnackBar was shown for this soft failure.
    expect(find.byType(SnackBar), findsNothing);
  });
}
