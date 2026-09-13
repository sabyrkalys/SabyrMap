import 'package:app/tracks/track_detail_screen.dart';
import 'package:app/tracks/track_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track({int? durationSeconds, double? elevationGainMeters}) {
  return Track(
    id: 't1',
    orgId: 'o1',
    ownerId: 'u1',
    name: 'Ridge Loop',
    points: const [TrackPoint(lat: 45.9, lng: 7.6), TrackPoint(lat: 46.0, lng: 7.7)],
    createdAt: DateTime.utc(2026, 9, 13),
    lengthMeters: 4200,
    durationSeconds: durationSeconds,
    elevationGainMeters: elevationGainMeters,
  );
}

void main() {
  testWidgets('shows the track name and formatted stats', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TrackDetailScreen(track: _track(durationSeconds: 5100, elevationGainMeters: 320))),
    );
    await tester.pump();

    expect(find.text('Ridge Loop'), findsOneWidget);
    expect(find.textContaining('4.2 км'), findsOneWidget);
    expect(find.textContaining('1 ч 25 мин'), findsOneWidget);
    expect(find.textContaining('+320 м'), findsOneWidget);
  });

  testWidgets('shows a dash for null duration and elevation gain', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrackDetailScreen(track: _track())));
    await tester.pump();

    expect(find.text('—'), findsNWidgets(2));
  });
}
