import 'package:app/compass/compass_source.dart';
import 'package:app/main.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compass/fakes.dart';
import 'tracks/fakes.dart';
import 'waypoints/fakes.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
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
  }

  testWidgets('opens straight into the app shell with no login step', (tester) async {
    await pumpApp(tester);

    expect(find.text('Вход'), findsNothing);
    expect(find.byKey(const Key('nav_settings')), findsOneWidget);
    expect(find.byKey(const Key('nav_map')), findsOneWidget);
  });

  testWidgets('hides the debug banner', (tester) async {
    await pumpApp(tester);

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).debugShowCheckedModeBanner, isFalse);
  });

  testWidgets('screen sets a transparent system navigation bar', (tester) async {
    await pumpApp(tester);

    final regions = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(regions.first.value.systemNavigationBarColor, Colors.transparent);
  });

  testWidgets('stays in the light theme when the system theme is dark', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester);

    final context = tester.element(find.byKey(const Key('nav_map')));
    expect(Theme.of(context).brightness, Brightness.light);
  });
}
