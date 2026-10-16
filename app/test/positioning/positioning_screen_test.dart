import 'package:app/positioning/positioning_screen.dart';
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/track_recording_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tracks/fake_location_source.dart';

void main() {
  testWidgets('record toggle icon switches between start and stop', (tester) async {
    final container = ProviderContainer(
      overrides: [],
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
}
