import 'package:app/compass/compass_screen.dart';
import 'package:app/compass/compass_source.dart';
import 'package:app/home/home_shell.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/positioning/positioning_screen.dart';
import 'package:app/settings/settings_screen.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:app/waypoints/waypoints_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../compass/fakes.dart';
import '../tracks/fakes.dart';
import '../waypoints/fakes.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
          tracksRepositoryProvider.overrideWithValue(FakeTracksRepository()),
          compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource()),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();
  }

  const navKeys = ['nav_settings', 'nav_map', 'nav_waypoints', 'nav_positioning', 'nav_compass'];

  // Index of the destination currently showing the selection indicator.
  int selectedIndex(WidgetTester tester) {
    final selected = [
      for (var i = 0; i < navKeys.length; i++)
        if (find
            .descendant(of: find.byKey(Key(navKeys[i])), matching: find.byKey(const Key('nav_indicator')))
            .evaluate()
            .isNotEmpty)
          i,
    ];
    expect(selected, hasLength(1));
    return selected.single;
  }

  testWidgets('starts on the map tab and switches tabs via the bottom nav', (tester) async {
    await pumpShell(tester);

    // All five destinations exist in one IndexedStack, so widget presence
    // alone doesn't prove which tab is active -- assert on the nav bar's
    // selected index instead.
    expect(selectedIndex(tester), 1);
    expect(find.byType(MapScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pump();
    expect(selectedIndex(tester), 0);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_waypoints')));
    await tester.pump();
    expect(selectedIndex(tester), 2);
    expect(find.byType(WaypointsListScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_positioning')));
    await tester.pump();
    expect(selectedIndex(tester), 3);
    expect(find.byType(PositioningScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_compass')));
    await tester.pump();
    expect(selectedIndex(tester), 4);
    expect(find.byType(CompassScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_map')));
    await tester.pump();
    expect(selectedIndex(tester), 1);
    expect(find.byType(MapScreen), findsOneWidget);
  });

  testWidgets('all five destination screens are built (kept alive offstage by IndexedStack)', (tester) async {
    await pumpShell(tester);

    // IndexedStack keeps every tab's widget tree built (that's how tab
    // state survives switching away and back) but marks the non-selected
    // ones offstage, so the default byType finder -- which skips offstage
    // elements -- needs skipOffstage: false here.
    expect(find.byType(MapScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(WaypointsListScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(PositioningScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(CompassScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(SettingsScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('bottom nav is 60 dp tall with 40 dp icons left-aligned at a 10 dp gap', (tester) async {
    await pumpShell(tester);

    final bar = find.byKey(const Key('bottom_nav'));
    expect(tester.getSize(bar).height, 60);
    final barLeft = tester.getTopLeft(bar).dx;

    for (var i = 0; i < navKeys.length; i++) {
      final icon = find.descendant(of: find.byKey(Key(navKeys[i])), matching: find.byType(SvgPicture));
      expect(tester.getSize(icon), const Size(40, 40));
      expect(tester.getTopLeft(icon).dx - barLeft, 10 + i * 50.0);
      expect(tester.getCenter(icon).dy, tester.getCenter(bar).dy);
    }
  });

  testWidgets('selection indicator is 48 dp square', (tester) async {
    await pumpShell(tester);

    expect(tester.getSize(find.byKey(const Key('nav_indicator'))), const Size(48, 48));
  });
}
