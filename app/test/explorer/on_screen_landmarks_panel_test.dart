import 'package:app/app/landmark_services_provider.dart';
import 'package:app/explorer/on_screen_landmarks_panel.dart';
import 'package:app/landmarks/on_screen/on_screen_sort.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:app/map/map_crosshair.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../landmarks/services/fixture.dart';
import 'landmark_test_helpers.dart';

void main() {
  late ServicesFixture f;

  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.root.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        landmarkServicesProvider.overrideWithValue(f.services),
        onScreenRegistryProvider.overrideWithValue(f.services.onScreen),
      ],
    );
    addTearDown(container.dispose);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48.5, 37.0));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: OnScreenLandmarksPanel()))),
      ),
    );
    // Список читается с диска: даём файловым операциям завершиться.
    for (var i = 0; i < 50 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  testWidgets('lists marks sorted by distance; the eye hides one on the map', (tester) async {
    late String near;
    await tester.runAsync(() async {
      near = await createWaypoint(f.services, 'Близко', f.paths.landmarks);
      await createWaypoint(f.services, 'Далеко', f.paths.landmarks);
      await f.services.settings.setString(
        SettingsKeys.onScreenSort,
        const OnScreenSort(field: OnScreenSortField.distance).encode(),
      );
    });
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('2 элем.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('on_screen_eye_Близко')));
    await tester.pump();
    expect(f.services.onScreen.isVisible(near), isFalse);
    expect(find.text('2 элем.'), findsOneWidget);
  });

  testWidgets('marks with the same name survive a re-sort', (tester) async {
    await tester.runAsync(() async {
      await createWaypoint(f.services, 'ЛБС', f.paths.landmarks);
      await createWaypoint(f.services, 'ЛБС', f.paths.landmarks);
      await createWaypoint(f.services, 'Альфа', f.paths.landmarks);
    });
    await pump(tester);
    expect(find.text('3 элем.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('on_screen_section_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Имя (z-a)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ЛБС'), findsNWidgets(2));
  });

  testWidgets('the menu offers only the show/hide that changes something', (tester) async {
    late String a;
    await tester.runAsync(() async {
      a = await createWaypoint(f.services, 'А', f.paths.landmarks);
      await createWaypoint(f.services, 'Б', f.paths.landmarks);
    });
    await pump(tester);
    Future<void> openMenu() async {
      await tester.tap(find.byKey(const Key('on_screen_section_menu_button')));
      await tester.pumpAndSettle();
    }

    Future<void> closeMenu() async {
      await tester.tap(find.text('ОТМЕНА'));
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(find.text('Сохранить все'), findsOneWidget);
    expect(find.text('Убрать все'), findsOneWidget);
    expect(find.text('Показать все'), findsNothing);
    expect(find.text('Скрыть все'), findsOneWidget);
    await closeMenu();

    f.services.onScreen.hide(a);
    await tester.pump();
    await openMenu();
    expect(find.text('Показать все'), findsOneWidget);
    expect(find.text('Скрыть все'), findsOneWidget);
    await tester.tap(find.text('Скрыть все'));
    await tester.pumpAndSettle();

    await openMenu();
    expect(find.text('Показать все'), findsOneWidget);
    expect(find.text('Скрыть все'), findsNothing);
  });
}
