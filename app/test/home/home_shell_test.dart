import 'package:app/compass/compass_screen.dart';
import 'package:app/compass/compass_source.dart';
import 'package:app/home/home_shell.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/positioning/positioning_screen.dart';
import 'package:app/settings/settings_panel.dart';
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
    expect(find.byType(SettingsPanel), findsOneWidget);

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

  testWidgets('all four tab screens are built (kept alive offstage by IndexedStack)', (tester) async {
    await pumpShell(tester);

    // IndexedStack keeps every tab's widget tree built (that's how tab
    // state survives switching away and back) but marks the non-selected
    // ones offstage, so the default byType finder -- which skips offstage
    // elements -- needs skipOffstage: false here.
    expect(find.byType(MapScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(WaypointsListScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(PositioningScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(CompassScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('settings opens as a panel over the map, its arrow pointing at the settings icon', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pump();

    expect(find.byType(MapScreen), findsOneWidget);
    final card = find.byKey(const Key('settings_panel_card'));
    final bar = find.byKey(const Key('bottom_nav'));
    final barTop = tester.getTopLeft(bar).dy;
    expect(tester.getBottomLeft(card).dy, barTop - 8);
    expect(tester.getTopLeft(card).dx, 5);
    expect(tester.getTopRight(card).dx, tester.view.physicalSize.width / tester.view.devicePixelRatio - 5);

    final arrow = find.byKey(const Key('settings_panel_arrow'));
    expect(tester.getSize(arrow), const Size(16, 8));
    final settingsIcon = find.descendant(of: find.byKey(const Key('nav_settings')), matching: find.byType(SvgPicture));
    expect(tester.getBottomLeft(arrow).dy, barTop);
    expect(tester.getCenter(arrow).dx, tester.getCenter(settingsIcon).dx);
  });

  testWidgets('switching to another tab closes the settings panel', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('nav_waypoints')));
    await tester.pump();

    expect(find.byType(SettingsPanel), findsNothing);
    expect(find.byType(SettingsPanel, skipOffstage: false), findsNothing);
  });

  testWidgets('bottom nav is a 250x60 panel 5 dp from the left edge, icons 40 dp at a 10 dp gap', (tester) async {
    await pumpShell(tester);

    final bar = find.byKey(const Key('bottom_nav'));
    expect(tester.getSize(bar), const Size(250, 60));
    expect(tester.getTopLeft(bar).dx, 5);

    for (var i = 0; i < navKeys.length; i++) {
      final icon = find.descendant(of: find.byKey(Key(navKeys[i])), matching: find.byType(SvgPicture));
      expect(tester.getSize(icon), const Size(40, 40));
      expect(tester.getTopLeft(icon).dx, 10 + i * 50.0);
      expect(tester.getCenter(icon).dy, tester.getCenter(bar).dy);
    }
  });

  testWidgets('bottom nav background is half transparent and the body extends under it', (tester) async {
    await pumpShell(tester);

    final decoration = tester.widget<Container>(find.byKey(const Key('bottom_nav'))).decoration! as BoxDecoration;
    expect(decoration.color!.a, closeTo(0.5, 0.01));
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).extendBody, isTrue);
  });

  testWidgets('selection indicator is 48 dp square', (tester) async {
    await pumpShell(tester);

    expect(tester.getSize(find.byKey(const Key('nav_indicator'))), const Size(48, 48));
  });
}
