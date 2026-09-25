import 'package:app/compass/compass_source.dart';
import 'package:app/home/home_shell.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/menu/menu_toggles.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../compass/fakes.dart';
import '../tracks/fakes.dart';
import '../waypoints/fakes.dart';

class _MemoryStore implements MenuTogglesStore {
  @override
  Future<Map<String, bool>> load() async => {};
  @override
  Future<void> save(Map<String, bool> values) async {}
}

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
          tracksRepositoryProvider.overrideWithValue(FakeTracksRepository()),
          compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource()),
          menuTogglesStoreProvider.overrideWithValue(_MemoryStore()),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();
  }

  const navKeys = ['nav_settings', 'nav_map', 'nav_waypoints', 'nav_positioning', 'nav_compass'];
  const panelKeys = ['settings_panel', 'maps_panel', 'waypoints_panel', 'positioning_panel', 'orientation_panel'];

  // Index of the destination showing the selection indicator, or null.
  int? selectedIndex(WidgetTester tester) {
    final selected = [
      for (var i = 0; i < navKeys.length; i++)
        if (find
            .descendant(of: find.byKey(Key(navKeys[i])), matching: find.byKey(const Key('nav_indicator')))
            .evaluate()
            .isNotEmpty)
          i,
    ];
    expect(selected.length, lessThanOrEqualTo(1));
    return selected.isEmpty ? null : selected.single;
  }

  Future<void> tapNav(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(Key(navKeys[index])));
    await tester.pumpAndSettle();
  }

  testWidgets('starts on the map with no tab selected and no panel', (tester) async {
    await pumpShell(tester);

    expect(find.byType(MapScreen), findsOneWidget);
    expect(selectedIndex(tester), isNull);
    for (final key in panelKeys) {
      expect(find.byKey(Key(key)), findsNothing);
    }
  });

  testWidgets('each icon opens its own panel over the map, arrow under that icon', (tester) async {
    await pumpShell(tester);

    for (var i = 0; i < navKeys.length; i++) {
      await tapNav(tester, i);
      expect(selectedIndex(tester), i);
      expect(find.byKey(Key(panelKeys[i])), findsOneWidget);
      expect(find.byType(MapScreen), findsOneWidget);

      final icon = find.descendant(of: find.byKey(Key(navKeys[i])), matching: find.byType(SvgPicture));
      final arrow = find.byKey(const Key('menu_panel_arrow'));
      expect(tester.getCenter(arrow).dx, tester.getCenter(icon).dx);
      expect(tester.getBottomLeft(arrow).dy, tester.getTopLeft(find.byKey(const Key('bottom_nav'))).dy);
    }
  });

  testWidgets('tapping the same icon again closes the panel', (tester) async {
    await pumpShell(tester);
    await tapNav(tester, 1);
    await tapNav(tester, 1);

    expect(find.byKey(const Key('maps_panel')), findsNothing);
    expect(selectedIndex(tester), isNull);
  });

  testWidgets('tapping the map closes the panel', (tester) async {
    await pumpShell(tester);
    await tapNav(tester, 2);

    await tester.tapAt(const Offset(300, 60));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypoints_panel')), findsNothing);
    expect(selectedIndex(tester), isNull);
  });

  testWidgets('another icon switches panels', (tester) async {
    await pumpShell(tester);
    await tapNav(tester, 0);
    await tapNav(tester, 4);

    expect(find.byKey(const Key('settings_panel')), findsNothing);
    expect(find.byKey(const Key('orientation_panel')), findsOneWidget);
    expect(selectedIndex(tester), 4);
  });

  testWidgets('compass icon is labelled Ориентирование', (tester) async {
    await pumpShell(tester);

    expect(find.bySemanticsLabel('Ориентирование'), findsOneWidget);
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
    await tapNav(tester, 1);

    expect(tester.getSize(find.byKey(const Key('nav_indicator'))), const Size(48, 48));
  });

  testWidgets('system back closes an open panel instead of leaving the app', (tester) async {
    await pumpShell(tester);
    await tapNav(tester, 1);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.byKey(const Key('maps_panel')), findsNothing);
    expect(find.byType(MapScreen), findsOneWidget);
  });

  testWidgets('panel and arrow respect a left system inset in landscape', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.625;
    tester.view.padding = const FakeViewPadding(left: 126);
    addTearDown(tester.view.reset);
    await pumpShell(tester);
    await tapNav(tester, 3);

    final icon = find.descendant(of: find.byKey(const Key('nav_positioning')), matching: find.byType(SvgPicture));
    expect(tester.getCenter(find.byKey(const Key('menu_panel_arrow'))).dx, tester.getCenter(icon).dx);
    expect(tester.getTopLeft(find.byKey(const Key('menu_panel_card'))).dx, 126 / 2.625 + 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a nav panel closes the crosshair card', (tester) async {
    await pumpShell(tester);
    await tester.tapAt(tester.getCenter(find.byType(MapLibreMap)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsOneWidget);

    await tapNav(tester, 1);
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });
}
