import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Track _track({String id = 't1', String name = 'Morning walk'}) {
  return Track(
    id: id,
    orgId: 'o1',
    ownerId: 'u1',
    name: name,
    points: const [TrackPoint(lat: 1.0, lng: 2.0), TrackPoint(lat: 1.1, lng: 2.1)],
    createdAt: DateTime.utc(2026, 8, 22),
  );
}

ProviderContainer _buildContainer({
  required FakeTracksRepository repo,
}) {
  return ProviderContainer(
    overrides: [
      tracksRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

void main() {
  test('initial state is an empty list', () {
    final container = _buildContainer(repo: FakeTracksRepository());
    addTearDown(container.dispose);

    expect(container.read(tracksControllerProvider), isEmpty);
  });

  group('loadTracks', () {
    test('populates state from the repository', () async {
      final repo = FakeTracksRepository(initial: [_track()]);
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await container.read(tracksControllerProvider.notifier).loadTracks();

      expect(container.read(tracksControllerProvider), hasLength(1));
    });
  });

  group('saveTrack', () {
    test('appends the created track to state and forwards timing to the repository', () async {
      final repo = FakeTracksRepository()..createResult = _track(id: 'server-id');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);
      final startedAt = DateTime.utc(2026, 9, 13, 8);
      final finishedAt = DateTime.utc(2026, 9, 13, 9, 30);

      await container.read(tracksControllerProvider.notifier).saveTrack(
            name: 'Morning walk',
            points: const [TrackPoint(lat: 1.0, lng: 2.0), TrackPoint(lat: 1.1, lng: 2.1)],
            startedAt: startedAt,
            finishedAt: finishedAt,
          );

      final state = container.read(tracksControllerProvider);
      expect(state, hasLength(1));
      expect(state.single.id, 'server-id');
      expect(repo.lastCreateStartedAt, startedAt);
      expect(repo.lastCreateFinishedAt, finishedAt);
    });

    test('leaves state unchanged and rethrows on failure', () async {
      final repo = FakeTracksRepository()..createResult = const TrackException('Could not create track');
      final container = _buildContainer(repo: repo);
      addTearDown(container.dispose);

      await expectLater(
        container.read(tracksControllerProvider.notifier).saveTrack(
              name: 'Morning walk',
              points: const [TrackPoint(lat: 1.0, lng: 2.0), TrackPoint(lat: 1.1, lng: 2.1)],
            ),
        throwsA(isA<TrackException>()),
      );

      expect(container.read(tracksControllerProvider), isEmpty);
    });
  });
}
