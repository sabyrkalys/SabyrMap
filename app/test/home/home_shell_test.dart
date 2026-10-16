import 'package:app/app_icons.dart';
import 'package:app/app/landmark_services_provider.dart';
import 'package:app/compass/compass_source.dart';
import 'package:app/explorer/on_screen_landmarks_panel.dart';
import 'package:app/home/home_shell.dart';
import 'package:app/map/map_bearing.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/menu/menu_toggles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../compass/fakes.dart';
import '../landmarks/services/fixture.dart';

class _MemoryStore implements MenuTogglesStore {
  @override
  Future<Map<String, bool>> load() async => {};
  @override
  Future<void> save(Map<String, bool> values) async {}
}

void main() {
  // Карта рисует метки из индекса настоящих сервисов во временной папке.
  late ServicesFixture fixture;
  setUp(() async => fixture = await ServicesFixture.create());
  tearDown(() => fixture.root.deleteSync(recursive: true));

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource()),
          menuTogglesStoreProvider.overrideWithValue(_MemoryStore()),
          landmarkServicesProvider.overrideWithValue(fixture.services),
          onScreenRegistryProvider.overrideWithValue(fixture.services.onScreen),
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

  testWidgets('«Позиционирование» shows the geo-target icon', (tester) async {
    await pumpShell(tester);
    final picture = tester.widget<SvgPicture>(
      find.descendant(of: find.byKey(const Key('nav_positioning')), matching: find.byType(SvgPicture)),
    );
    expect((picture.bytesLoader as SvgAssetLoader).assetName, AppIcons.geoTarget);
  });

  testWidgets('opening a nav panel closes the crosshair card', (tester) async {
    await pumpShell(tester);
    await tester.tapAt(tester.getCenter(find.byType(MapLibreMap)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsOneWidget);

    await tapNav(tester, 1);
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });

  testWidgets('while a set is drawn its panel sits at the bottom edge and the nav goes above it', (tester) async {
    await pumpShell(tester);
    final screen = tester.getSize(find.byType(HomeShell));
    final navBottom = tester.getBottomLeft(find.byKey(const Key('bottom_nav'))).dy;

    fixture.services.editMode.startNew(LandmarkType.set);
    await tester.pump();
    await tester.pump();
    final panel = find.byKey(const Key('set_panel'));
    expect(panel, findsOneWidget);
    expect(tester.getBottomLeft(panel).dy, screen.height);
    expect(find.byKey(const Key('nav_map')), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byKey(const Key('bottom_nav'))).dy,
      lessThanOrEqualTo(tester.getTopLeft(panel).dy),
    );

    fixture.services.editMode.close();
    await tester.pump();
    await tester.pump();
    expect(tester.getBottomLeft(find.byKey(const Key('bottom_nav'))).dy, navBottom);
  });

  testWidgets('«Метки на экране» opens with the main menu above it; a tab there closes the sheet and opens the tab', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('nav_waypoints')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Метки на экране'));
    await tester.pumpAndSettle();

    final sheetNav = find.byKey(const Key('bottom_nav'));
    // Два меню: под шторкой (в HomeShell) и над ней — то, что над ней, выше.
    expect(sheetNav, findsNWidgets(2));
    final panelTop = tester.getTopLeft(find.byType(OnScreenLandmarksPanel)).dy;
    expect(tester.getBottomLeft(sheetNav.last).dy, lessThanOrEqualTo(panelTop));
    // Кнопки «+» и «−» — тоже над шторкой.
    final zoomIn = find.byKey(const Key('zoom_in_button'));
    expect(zoomIn, findsNWidgets(2));
    expect(tester.getBottomLeft(zoomIn.last).dy, lessThanOrEqualTo(panelTop));

    await tester.tap(find.descendant(of: sheetNav.last, matching: find.byKey(const Key('nav_map'))));
    await tester.pumpAndSettle();
    expect(find.byType(OnScreenLandmarksPanel), findsNothing);
    expect(find.byKey(const Key('maps_panel')), findsOneWidget);
  });

  testWidgets('any touch on the map closes a map sheet and a menu panel — a drag too, not only a tap', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('nav_waypoints')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Метки на экране'));
    await tester.pumpAndSettle();
    expect(find.byType(OnScreenLandmarksPanel), findsOneWidget);

    await tester.dragFrom(
      tester.getTopLeft(find.byKey(const Key('sheet_map_area'))) + const Offset(200, 80),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnScreenLandmarksPanel), findsNothing);

    await tester.tap(find.byKey(const Key('nav_map')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('maps_panel')), findsOneWidget);
    await tester.dragFrom(const Offset(300, 60), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('maps_panel')), findsNothing);
  });

  testWidgets('a rotated map shows the compass with a lock; a tap turns the map north instead of opening the menu', (
    tester,
  ) async {
    await pumpShell(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    expect(find.byKey(const Key('nav_compass_lock')), findsNothing);

    var northUps = 0;
    container.read(mapBearingProvider.notifier)
      ..attach(() => northUps++)
      ..update(37);
    await tester.pump();
    expect(find.byKey(const Key('nav_compass_lock')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_compass')));
    await tester.pumpAndSettle();
    expect(northUps, 1);
    expect(find.byKey(const Key('orientation_panel')), findsNothing);

    container.read(mapBearingProvider.notifier).update(0.2);
    await tester.pump();
    expect(find.byKey(const Key('nav_compass_lock')), findsNothing);
    await tester.tap(find.byKey(const Key('nav_compass')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('orientation_panel')), findsOneWidget);
  });
}
