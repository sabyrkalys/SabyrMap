import 'package:app/mediafile/mediafile_folder_screen.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:app/waypoints/waypoints_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';
import 'fakes.dart';

Waypoint _waypoint({required String id, required String name}) => Waypoint(
      id: id,
      orgId: 'o1',
      ownerId: 'u1',
      name: name,
      type: 'water',
      note: null,
      color: null,
      lat: 1,
      lng: 2,
      canEdit: true,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  testWidgets('shows an empty message when there are no waypoints', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
        ],
        child: const MaterialApp(home: WaypointsListScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Пока нет меток'), findsOneWidget);
  });

  testWidgets('lists waypoints with name and type label', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final repo = FakeWaypointsRepository(
      initial: [_waypoint(id: 'w1', name: 'Родник')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          waypointsRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: WaypointsListScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Родник'), findsOneWidget);
    expect(find.text('вода'), findsOneWidget);
  });

  testWidgets('AppBar action opens the icon files screen', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
        ],
        child: const MaterialApp(home: WaypointsListScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('waypoint_files_button')));
    await tester.pump();
    // A real MediaFileFolderScreen resolves its folder via path_provider,
    // which has no platform-channel mock under flutter test (same
    // limitation already accepted elsewhere in this codebase, e.g.
    // IconLibraryScanner's default constructor) -- a single pump is enough
    // to prove the navigation happened, without waiting for that call to
    // settle.
    await tester.pump();

    expect(find.byType(MediaFileFolderScreen), findsOneWidget);
  });
}
