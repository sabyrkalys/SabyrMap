import 'package:app/compass/compass_screen.dart';
import 'package:app/compass/compass_source.dart';
import 'package:app/home/home_shell.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/settings/settings_screen.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:app/waypoints/waypoints_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';
import '../compass/fakes.dart';
import '../tracks/fakes.dart';
import '../waypoints/fakes.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
          tracksRepositoryProvider.overrideWithValue(FakeTracksRepository()),
          compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource()),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();
  }

  int selectedIndex(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  testWidgets('starts on the map tab and switches tabs via the bottom nav', (tester) async {
    await pumpShell(tester);

    // All four destinations exist in one IndexedStack, so widget presence
    // alone doesn't prove which tab is active -- assert on the nav bar's
    // selected index instead.
    expect(selectedIndex(tester), 0);

    await tester.tap(find.byKey(const Key('nav_waypoints')));
    await tester.pump();
    expect(selectedIndex(tester), 1);

    await tester.tap(find.byKey(const Key('nav_compass')));
    await tester.pump();
    expect(selectedIndex(tester), 2);

    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pump();
    expect(selectedIndex(tester), 3);

    await tester.tap(find.byKey(const Key('nav_map')));
    await tester.pump();
    expect(selectedIndex(tester), 0);
  });

  testWidgets('all four destination screens are built (kept alive offstage by IndexedStack)', (tester) async {
    await pumpShell(tester);

    // IndexedStack keeps every tab's widget tree built (that's how tab
    // state survives switching away and back) but marks the non-selected
    // ones offstage, so the default byType finder -- which skips offstage
    // elements -- needs skipOffstage: false here.
    expect(find.byType(MapScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(WaypointsListScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(CompassScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(SettingsScreen, skipOffstage: false), findsOneWidget);
  });
}
