import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoint_types.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';
import '../waypoints/fakes.dart';

void main() {
  testWidgets('MapScreen builds without throwing and shows a logout action', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final repo = FakeAuthRepository(
      meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          tokenStorageProvider.overrideWithValue(storage),
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
        ],
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });

  testWidgets('tapping logout calls AuthController.logout', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final repo = FakeAuthRepository(
      meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        tokenStorageProvider.overrideWithValue(storage),
        waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pump();

    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  testWidgets('creating a waypoint via the controller updates the rendered state', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final authRepo = FakeAuthRepository(
      meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
    );
    final waypointsRepo = FakeWaypointsRepository()
      ..createResult = Waypoint(
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
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        tokenStorageProvider.overrideWithValue(storage),
        waypointsRepositoryProvider.overrideWithValue(waypointsRepo),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    // MapLibreMap has no real platform view under flutter test, so this
    // drives WaypointsController.createWaypoint directly (the same call
    // _onMapLongClick makes after the form is submitted) rather than
    // simulating a real long-press gesture on the (unrenderable) map
    // widget. This verifies the state MapScreen listens to updates
    // correctly; the long-press gesture itself is covered by manual
    // device verification (see Step 8 in the task brief).
    await container.read(waypointsControllerProvider.notifier).createWaypoint(
          ownerId: 'u1',
          name: 'Summit',
          type: 'generic',
          note: '',
          lat: 1.0,
          lng: 2.0,
        );

    expect(container.read(waypointsControllerProvider), hasLength(1));
    expect(container.read(waypointsControllerProvider).single.name, 'Summit');
  });

  group('circleOptionsForWaypoint', () {
    Waypoint waypointWith({required String ownerId, required String type}) => Waypoint(
          id: 'w1',
          orgId: 'o1',
          ownerId: ownerId,
          name: 'Summit',
          type: type,
          note: null,
          lat: 1.0,
          lng: 2.0,
          canEdit: true,
          createdAt: DateTime.utc(2026, 8, 22),
        );

    test('falls back to the default type color for an unrecognized type', () {
      final waypoint = waypointWith(ownerId: 'u1', type: 'not-a-real-type');

      final options = circleOptionsForWaypoint(waypoint, 'u1');

      expect(options.circleColor, waypointTypeColors[defaultWaypointType]);
    });

    test('uses the type color for a recognized type', () {
      final waypoint = waypointWith(ownerId: 'u1', type: 'danger');

      final options = circleOptionsForWaypoint(waypoint, 'u1');

      expect(options.circleColor, waypointTypeColors['danger']);
    });

    test('own waypoints get a thin white stroke', () {
      final waypoint = waypointWith(ownerId: 'u1', type: 'generic');

      final options = circleOptionsForWaypoint(waypoint, 'u1');

      expect(options.circleStrokeColor, '#FFFFFF');
      expect(options.circleStrokeWidth, 1);
    });

    test('shared waypoints get a thicker black stroke', () {
      final waypoint = waypointWith(ownerId: 'someone-else', type: 'generic');

      final options = circleOptionsForWaypoint(waypoint, 'u1');

      expect(options.circleStrokeColor, '#000000');
      expect(options.circleStrokeWidth, 2);
    });
  });
}
