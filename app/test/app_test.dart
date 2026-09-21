import 'package:app/compass/compass_source.dart';
import 'package:app/main.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compass/fakes.dart';
import 'tracks/fakes.dart';
import 'waypoints/fakes.dart';

void main() {
  testWidgets('opens straight into the app shell with no login step', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
          tracksRepositoryProvider.overrideWithValue(FakeTracksRepository()),
          compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource()),
        ],
        child: const AlpineQuestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsNothing);
    expect(find.byKey(const Key('nav_settings')), findsOneWidget);
    expect(find.byKey(const Key('nav_map')), findsOneWidget);
  });
}
