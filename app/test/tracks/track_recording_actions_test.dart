import 'package:app/app/landmark_services_provider.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/track_recording_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../landmarks/services/fixture.dart';

void main() {
  late ServicesFixture f;
  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.dispose());

  testWidgets('a recorded track is saved as a .trk file in the unsorted landmarks, not sent anywhere', (tester) async {
    final container = ProviderContainer(
      overrides: [
        landmarkServicesProvider.overrideWithValue(f.services),
        markerGroupFoldersProvider.overrideWithValue(
          MarkerGroupFolders(unsorted: f.paths.importDefault, myMarkers: f.paths.landmarks),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final messenger = ScaffoldMessenger.of(tester.element(find.byType(SizedBox)));
    final start = DateTime.utc(2026, 10, 16, 8);

    final path = await tester.runAsync(
      () => saveRecordedTrack(
        container,
        messenger,
        name: 'Утро',
        points: [
          TrackPoint(lat: 48.5, lng: 37.0, elevationMeters: 200, time: start),
          TrackPoint(lat: 48.51, lng: 37.01, elevationMeters: 210, time: start.add(const Duration(minutes: 5))),
        ],
      ),
    );
    await tester.pump();

    expect(p.extension(path!), '.trk');
    expect(p.dirname(path), f.paths.importDefault);
    expect(find.text('Трек «Утро» сохранён'), findsOneWidget);
    final track = (await tester.runAsync(() => f.services.repository.load(path)))!.content as TrackObject;
    expect(track.userMetadata.name, 'Утро');
    expect(track.segments.single.locations, hasLength(2));
    expect(track.segments.single.locations.last.valueOf(LocationValueType.elevation)?.value, 210000);
    expect(f.services.index.byType(LandmarkType.track).single.path, path);
  });
}
