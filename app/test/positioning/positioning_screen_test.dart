import 'package:app/positioning/positioning_screen.dart';
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/track_recording_controller.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tracks/fake_location_source.dart';
import '../tracks/fakes.dart';

void main() {
  testWidgets('record toggle icon switches between start and stop', (tester) async {
    final container = ProviderContainer(
      overrides: [tracksRepositoryProvider.overrideWithValue(FakeTracksRepository())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PositioningScreen()),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle), findsNothing);
  });

  testWidgets('stopping a too-short recording shows a message and does not open the save form', (tester) async {
    final locationSource = FakeLocationSource();
    final container = ProviderContainer(
      overrides: [
        tracksRepositoryProvider.overrideWithValue(FakeTracksRepository()),
        locationSourceProvider.overrideWithValue(locationSource),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PositioningScreen()),
      ),
    );
    await tester.pump();

    // Start recording.
    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();

    // Emit a single point -- not enough to save a valid track (needs >= 2).
    locationSource.emit(const TrackPoint(lat: 1.0, lng: 2.0));
    await tester.pump();

    // Stop recording.
    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Трек слишком короткий, чтобы сохранить'), findsOneWidget);
    expect(find.byKey(const Key('track_name_field')), findsNothing);
  });

  testWidgets('a TrackException on save shows a SnackBar with the error message', (tester) async {
    final locationSource = FakeLocationSource();
    final tracksRepo = FakeTracksRepository()..createResult = const TrackException('Could not create track');
    final container = ProviderContainer(
      overrides: [
        tracksRepositoryProvider.overrideWithValue(tracksRepo),
        locationSourceProvider.overrideWithValue(locationSource),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PositioningScreen()),
      ),
    );
    await tester.pump();

    // Start recording and emit enough points for a valid track.
    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();
    locationSource.emit(const TrackPoint(lat: 1.0, lng: 2.0));
    await tester.pump();
    locationSource.emit(const TrackPoint(lat: 1.1, lng: 2.1));
    await tester.pump();

    // Stop recording -- this opens the save-name sheet.
    await tester.tap(find.byKey(const Key('track_record_toggle')));
    await tester.pumpAndSettle();

    // Submit the save form.
    await tester.enterText(find.byKey(const Key('track_name_field')), 'My track');
    await tester.pump();
    await tester.tap(find.byKey(const Key('track_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Could not create track'), findsOneWidget);
  });
}
