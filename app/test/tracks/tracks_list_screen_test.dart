import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/tracks/tracks_list_screen.dart';
import 'package:flutter/material.dart';
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
    createdAt: DateTime.utc(2026, 9, 13),
    lengthMeters: 4200,
    durationSeconds: 5100,
    elevationGainMeters: 320,
  );
}

void main() {
  testWidgets('shows an empty message when there are no tracks', (tester) async {
    final container = ProviderContainer(
      overrides: [
        tracksRepositoryProvider.overrideWithValue(FakeTracksRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: TracksListScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Пока нет сохранённых треков'), findsOneWidget);
  });

  testWidgets('lists tracks with formatted length and duration', (tester) async {
    final container = ProviderContainer(
      overrides: [
        tracksRepositoryProvider.overrideWithValue(FakeTracksRepository(initial: [_track()])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: TracksListScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Morning walk'), findsOneWidget);
    expect(find.textContaining('4.2 км'), findsOneWidget);
    expect(find.textContaining('1 ч 25 мин'), findsOneWidget);
  });

  testWidgets('tapping a track card navigates to its detail screen', (tester) async {
    final container = ProviderContainer(
      overrides: [
        tracksRepositoryProvider.overrideWithValue(FakeTracksRepository(initial: [_track()])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: TracksListScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning walk'));
    await tester.pumpAndSettle();

    expect(find.text('Пока нет сохранённых треков'), findsNothing);
    expect(find.byKey(const Key('track_stats_row')), findsOneWidget);
  });
}
