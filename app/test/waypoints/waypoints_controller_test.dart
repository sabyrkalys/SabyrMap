import 'package:app/auth/token_storage.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';
import 'fakes.dart';

Waypoint _waypoint({
  String id = 'w1',
  String ownerId = 'u1',
  String type = 'generic',
  String? note,
  String? color,
}) {
  return Waypoint(
    id: id,
    orgId: 'o1',
    ownerId: ownerId,
    name: 'Test',
    type: type,
    note: note,
    color: color,
    lat: 1.0,
    lng: 2.0,
    canEdit: true,
    createdAt: DateTime.utc(2026, 8, 22),
  );
}

ProviderContainer _buildContainer({
  required FakeWaypointsRepository repo,
  TokenStorage? storage,
}) {
  final tokenStorage = storage ?? (FakeTokenStorage()..write('tok-1'));
  return ProviderContainer(
    overrides: [
      waypointsRepositoryProvider.overrideWithValue(repo),
      tokenStorageProvider.overrideWithValue(tokenStorage),
    ],
  );
}

void main() {
  test('initial state is an empty list', () {
    final container = _buildContainer(repo: FakeWaypointsRepository());
    addTearDown(container.dispose);

    expect(container.read(waypointsControllerProvider), isEmpty);
  });

  group('loadWaypoints', () {
    test('populates state from the repository', () async {
      final repo = FakeWaypointsRepository(initial: [_waypoint()]);
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      expect(container.read(waypointsControllerProvider), hasLength(1));
    });

    test('leaves state empty when no token is stored', () async {
      final storage = FakeTokenStorage();
      final container = _buildContainer(repo: FakeWaypointsRepository(initial: [_waypoint()]), storage: storage);
      addTearDown(container.dispose);

      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      expect(container.read(waypointsControllerProvider), isEmpty);
    });
  });

  group('createWaypoint', () {
    test('adds the waypoint optimistically then replaces it with the server result', () async {
      final repo = FakeWaypointsRepository()..createResult = _waypoint(id: 'server-id');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await container.read(waypointsControllerProvider.notifier).createWaypoint(
            ownerId: 'u1',
            name: 'Test',
            type: 'generic',
            note: '',
            color: null,
            lat: 1.0,
            lng: 2.0,
          );

      final state = container.read(waypointsControllerProvider);
      expect(state, hasLength(1));
      expect(state.single.id, 'server-id');
    });

    test('passes color through to the repository and optimistic state', () async {
      final repo = FakeWaypointsRepository()
        ..createResult = _waypoint(id: 'w1', color: '#FF00AA');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await container.read(waypointsControllerProvider.notifier).createWaypoint(
            ownerId: 'u1',
            name: 'Test',
            type: 'generic',
            note: '',
            color: '#FF00AA',
            lat: 1.0,
            lng: 2.0,
          );

      expect(container.read(waypointsControllerProvider).single.color, '#FF00AA');
    });

    test('rolls back the optimistic waypoint and rethrows on failure', () async {
      final repo = FakeWaypointsRepository()..createResult = const WaypointException('Could not create waypoint');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await expectLater(
        container.read(waypointsControllerProvider.notifier).createWaypoint(
              ownerId: 'u1',
              name: 'Test',
              type: 'generic',
              note: '',
              color: null,
              lat: 1.0,
              lng: 2.0,
            ),
        throwsA(isA<WaypointException>()),
      );

      expect(container.read(waypointsControllerProvider), isEmpty);
    });
  });

  group('updateWaypoint', () {
    test('applies the update optimistically then replaces it with the server result', () async {
      final repo = FakeWaypointsRepository(initial: [_waypoint()])
        ..updateResult = _waypoint(type: 'danger', note: 'Careful');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      await container.read(waypointsControllerProvider.notifier).updateWaypoint(
            'w1',
            name: 'Test',
            type: 'danger',
            note: 'Careful',
            color: null,
          );

      final state = container.read(waypointsControllerProvider);
      expect(state.single.type, 'danger');
      expect(state.single.note, 'Careful');
    });

    test('passes color through to the repository and the resulting state', () async {
      // Uses a color distinct from any type's default so this can't be
      // masked by a call site that dropped the argument and happened to
      // land on a coincidentally-matching default color.
      final repo = FakeWaypointsRepository(initial: [_waypoint()])
        ..updateResult = _waypoint(color: '#123456');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      await container.read(waypointsControllerProvider.notifier).updateWaypoint(
            'w1',
            name: 'Test',
            type: 'generic',
            note: '',
            color: '#123456',
          );

      expect(repo.lastUpdateColor, '#123456');
      expect(container.read(waypointsControllerProvider).single.color, '#123456');
    });

    test('rolls back to the previous waypoint and rethrows on failure', () async {
      final repo = FakeWaypointsRepository(initial: [_waypoint(type: 'generic')])
        ..updateResult = const WaypointException('Could not update waypoint');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      await expectLater(
        container.read(waypointsControllerProvider.notifier).updateWaypoint(
              'w1',
              name: 'Test',
              type: 'danger',
              note: '',
              color: null,
            ),
        throwsA(isA<WaypointException>()),
      );

      expect(container.read(waypointsControllerProvider).single.type, 'generic');
    });
  });

  group('deleteWaypoint', () {
    test('removes the waypoint on success', () async {
      final repo = FakeWaypointsRepository(initial: [_waypoint()]);
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      await container.read(waypointsControllerProvider.notifier).deleteWaypoint('w1');

      expect(container.read(waypointsControllerProvider), isEmpty);
    });

    test('restores the waypoint and rethrows on failure', () async {
      final repo = FakeWaypointsRepository(initial: [_waypoint()])
        ..deleteResult = const WaypointException('Could not delete waypoint');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      await container.read(waypointsControllerProvider.notifier).loadWaypoints();

      await expectLater(
        container.read(waypointsControllerProvider.notifier).deleteWaypoint('w1'),
        throwsA(isA<WaypointException>()),
      );

      expect(container.read(waypointsControllerProvider), hasLength(1));
    });
  });
}
