import 'package:app/icons/waypoint_icon_assignments_controller.dart';
import 'package:app/icons/waypoint_icon_store.dart';
import 'dart:math';

import 'package:app/map/map_crosshair.dart';
import 'package:app/map/map_screen.dart';
import 'package:app/map/map_target.dart';
import 'package:app/menu/menu_toggles.dart';
import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/track_recording_controller.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoint_types.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../icons/fakes.dart';
import '../tracks/fake_location_source.dart';
import '../tracks/fakes.dart';
import '../waypoints/fakes.dart';

class _NoopTogglesStore implements MenuTogglesStore {
  @override
  Future<Map<String, bool>> load() async => {};
  @override
  Future<void> save(Map<String, bool> values) async {}
}

// riverpod 3.x's `Override` type isn't part of the package's public export
// surface (package:riverpod/riverpod.dart and package:flutter_riverpod
// don't `show` it), so this helper can't name it as an explicit return
// type the way earlier riverpod versions allowed. Returning the list
// literal without an explicit annotation lets the compiler infer it as
// `List<Override>` from the `.overrideWithValue()` calls inside, which is
// assignable everywhere `ProviderContainer`/`ProviderScope` expect one.
_baseOverrides({
  FakeWaypointsRepository? waypointsRepo,
  FakeTracksRepository? tracksRepo,
  FakeWaypointIconStore? iconStore,
}) {
  return [
    waypointsRepositoryProvider.overrideWithValue(waypointsRepo ?? FakeWaypointsRepository()),
    tracksRepositoryProvider.overrideWithValue(tracksRepo ?? FakeTracksRepository()),
    // MapScreen loads the local icon assignments on open; the real store
    // talks to flutter_secure_storage, which has no platform channel under
    // flutter test.
    waypointIconStoreProvider.overrideWithValue(iconStore ?? FakeWaypointIconStore()),
    menuTogglesStoreProvider.overrideWithValue(_NoopTogglesStore()),
  ];
}

void main() {
  testWidgets('MapScreen builds without throwing', (tester) async {

    await tester.pumpWidget(
      ProviderScope(
        overrides: _baseOverrides(),
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(MapScreen), findsOneWidget);
  });

  testWidgets('creating a waypoint via the controller updates the rendered state', (tester) async {
    final waypointsRepo = FakeWaypointsRepository()
      ..createResult = Waypoint(
        id: 'w1',
        orgId: 'o1',
        ownerId: 'u1',
        name: 'Summit',
        type: 'generic',
        note: null,
        lat: 1.0,
        lng: 2.0,
        canEdit: true,
        createdAt: DateTime.utc(2026, 8, 22),
      );
    final container = ProviderContainer(
      overrides: _baseOverrides(waypointsRepo: waypointsRepo),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    // MapLibreMap has no real platform view under flutter test, so this
    // drives WaypointsController.createWaypoint directly (the same call
    // _onMapLongClick makes after the form is submitted) rather than
    // simulating a real long-press gesture on the (unrenderable) map
    // widget. This verifies the state MapScreen listens to updates
    // correctly; the long-press gesture itself is covered by manual
    // device verification (see Step 9 in the task brief).
    await container.read(waypointsControllerProvider.notifier).createWaypoint(
          name: 'Summit',
          type: 'generic',
          note: '',
          color: null,
          lat: 1.0,
          lng: 2.0,
        );

    expect(container.read(waypointsControllerProvider), hasLength(1));
    expect(container.read(waypointsControllerProvider).single.name, 'Summit');
  });

  // Taps reach the map as MapLibre onMapClick calls with projection
  // (physical) pixels, the way the Android plugin reports them.
  void mapClickAt(WidgetTester tester, Offset logical, [LatLng coordinates = const LatLng(48, 37.8)]) {
    final ratio = tester.view.devicePixelRatio;
    tester.widget<MapLibreMap>(find.byType(MapLibreMap)).onMapClick!(
      Point<double>(logical.dx * ratio, logical.dy * ratio),
      coordinates,
    );
  }

  Offset screenCenter(WidgetTester tester) => tester.getCenter(find.byType(MapLibreMap));

  Future<ProviderContainer> pumpMap(WidgetTester tester) async {
    final container = ProviderContainer(overrides: _baseOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: MapScreen())),
    );
    await tester.pump();
    return container;
  }

  testWidgets('crosshair, zoom buttons, no «Метка здесь» button, no long-press wiring', (tester) async {
    await pumpMap(tester);

    expect(find.byKey(const Key('map_crosshair')), findsOneWidget);
    expect(find.byKey(const Key('zoom_in_button')), findsOneWidget);
    expect(find.byKey(const Key('zoom_out_button')), findsOneWidget);
    expect(find.text('Метка здесь'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.widget<MapLibreMap>(find.byType(MapLibreMap)).onMapLongClick, isNull);
  });

  testWidgets('tapping the crosshair opens the card above it; tapping again closes it', (tester) async {
    await pumpMap(tester);

    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('crosshair_menu'));
    expect(card, findsOneWidget);
    expect(
      tester.getBottomLeft(find.byKey(const Key('crosshair_menu_triangle'))).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(const Key('map_crosshair'))).dy),
    );
    expect(
      tester.getCenter(find.byKey(const Key('crosshair_menu_triangle'))).dx,
      closeTo(tester.getCenter(find.byKey(const Key('map_crosshair'))).dx, 0.5),
    );

    // A second tap on the crosshair lands on the card's barrier.
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
  });

  testWidgets('tapping outside the card closes it', (tester) async {
    await pumpMap(tester);
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });

  testWidgets('«Задать цель» closes the card and arms picking; with a target the item is «Убрать цель»', (tester) async {
    final container = await pumpMap(tester);
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Задать цель'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
    expect(container.read(mapTargetProvider), isA<MapTargetPicking>());

    container.read(mapTargetProvider.notifier).pick(const LatLng(48, 37.8));
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Убрать цель'));
    await tester.pumpAndSettle();
    expect(container.read(mapTargetProvider), isA<MapTargetNone>());
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });

  testWidgets('distance label follows «Статус цели»', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));
    container.read(mapTargetProvider.notifier)
      ..startPicking()
      ..pick(const LatLng(48, 37.8));
    await tester.pump();
    expect(find.byKey(const Key('target_distance_label')), findsOneWidget);
    expect(find.text('0 м'), findsOneWidget);

    container.read(menuTogglesProvider.notifier).set(MenuToggle.waypointsTargetStatus, false);
    await tester.pump();
    expect(find.byKey(const Key('target_distance_label')), findsNothing);
  });

  testWidgets('«Новая метка...» before the map settles reports the map is not ready', (tester) async {
    await pumpMap(tester);
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Новая метка...'));
    await tester.pumpAndSettle();
    expect(find.text('Карта ещё не готова'), findsOneWidget);
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });

  testWidgets('a map tap away from the crosshair does not open the card', (tester) async {
    await pumpMap(tester);
    mapClickAt(tester, screenCenter(tester) + const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });

  testWidgets('while picking, a tap on the crosshair sets the target instead of opening the card', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapTargetProvider.notifier).startPicking();
    mapClickAt(tester, screenCenter(tester), const LatLng(1, 2));
    await tester.pumpAndSettle();
    expect(container.read(mapTargetProvider).point, const LatLng(1, 2));
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });

  testWidgets('a MapLibre click on the crosshair does not toggle the card by itself', (tester) async {
    // The finger tap is handled on the Flutter side; if the map also
    // reported it, the card would open and close again at once.
    await pumpMap(tester);
    mapClickAt(tester, screenCenter(tester));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });

  testWidgets('while picking, a finger tap on the crosshair does not open the card', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapTargetProvider.notifier).startPicking();
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
    expect(container.read(mapTargetProvider), isA<MapTargetPicking>());
  });

  testWidgets('a drag that starts on the crosshair does not open the card', (tester) async {
    await pumpMap(tester);
    await tester.dragFrom(screenCenter(tester), const Offset(120, 40));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
  });

  testWidgets('a touch on the crosshair still reaches the map', (tester) async {
    await pumpMap(tester);
    final mapObjects = find
        .descendant(of: find.byType(MapLibreMap), matching: find.byWidgetPredicate((_) => true))
        .evaluate()
        .map((e) => e.renderObject)
        .toSet();
    final hitTargets = tester.hitTestOnBinding(screenCenter(tester)).path.map((e) => e.target).toSet();
    expect(hitTargets.intersection(mapObjects), isNotEmpty);
  });

  testWidgets('crosshair and distance label let map gestures through', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));
    container.read(mapTargetProvider.notifier)
      ..startPicking()
      ..pick(const LatLng(48, 37.8));
    await tester.pump();

    for (final key in ['map_crosshair', 'target_distance_label']) {
      final ignoring = tester
          .widgetList<IgnorePointer>(find.ancestor(of: find.byKey(Key(key)), matching: find.byType(IgnorePointer)))
          .any((w) => w.ignoring);
      expect(ignoring, isTrue, reason: key);
    }
  });

  testWidgets('lines do not swallow taps, so the crosshair still opens the card over the target line', (tester) async {
    await pumpMap(tester);
    final consumed = tester.widget<MapLibreMap>(find.byType(MapLibreMap)).annotationConsumeTapEvents;
    expect(consumed, isNot(contains(AnnotationType.line)));
    expect(consumed, containsAll([AnnotationType.circle, AnnotationType.symbol]));
  });

  testWidgets('the map is capped at zoom 20 and the old coordinate HUD is gone', (tester) async {
    await pumpMap(tester);
    final map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));
    expect(map.minMaxZoomPreference.maxZoom, 20);
    expect(find.byKey(const Key('coordinate_hud')), findsNothing);
  });

  group('circleOptionsForWaypoint', () {
    Waypoint waypointWith({required String ownerId, required String type}) => Waypoint(
          id: 'w1',
          orgId: 'o1',
          ownerId: ownerId,
          name: 'Summit',
          type: type,
          note: null,
          lat: 1.0,
          lng: 2.0,
          canEdit: true,
          createdAt: DateTime.utc(2026, 8, 22),
        );

    test('falls back to the default type color for an unrecognized type', () {
      final waypoint = waypointWith(ownerId: 'u1', type: 'not-a-real-type');

      final options = circleOptionsForWaypoint(waypoint);

      expect(options.circleColor, waypointTypeColors[defaultWaypointType]);
    });

    test('uses the type color for a recognized type', () {
      final waypoint = waypointWith(ownerId: 'u1', type: 'danger');

      final options = circleOptionsForWaypoint(waypoint);

      expect(options.circleColor, waypointTypeColors['danger']);
    });

    test('waypoints get a thin white stroke', () {
      final waypoint = waypointWith(ownerId: 'u1', type: 'generic');

      final options = circleOptionsForWaypoint(waypoint);

      expect(options.circleStrokeColor, '#FFFFFF');
      expect(options.circleStrokeWidth, 1);
    });

    test('a custom color overrides the type color', () {
      final waypoint = Waypoint(
        id: 'w1',
        orgId: 'o1',
        ownerId: 'u1',
        name: 'Summit',
        type: 'danger',
        note: null,
        color: '#123456',
        lat: 1.0,
        lng: 2.0,
        canEdit: true,
        createdAt: DateTime.utc(2026, 8, 22),
      );

      final options = circleOptionsForWaypoint(waypoint);

      expect(options.circleColor, '#123456');
    });
  });

  testWidgets('opening the map loads the locally-stored icon assignments', (tester) async {
    final iconStore = FakeWaypointIconStore()..icons.addAll({'w1': 'camp.png'});
    final container = ProviderContainer(
      overrides: _baseOverrides(iconStore: iconStore),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The assignments are what decide circle-vs-symbol rendering, so they
    // must be in state by the time the first sync runs. The rendering itself
    // needs a real MapLibreMapController (none under flutter test, so
    // _syncSymbols returns at its readiness guard) and is covered by manual
    // device verification, same precedent as the other map render paths.
    expect(container.read(waypointIconAssignmentsControllerProvider), {'w1': 'camp.png'});
    expect(find.byType(MapScreen), findsOneWidget);
  });

  group('renderModeForWaypoint', () {
    test('no assigned icon -> circle', () {
      expect(renderModeForWaypoint(null), WaypointRenderMode.circle);
    });

    test('an assigned icon -> symbol', () {
      expect(renderModeForWaypoint('camp.png'), WaypointRenderMode.symbol);
    });
  });

  testWidgets('builds without throwing when the location source has no position available', (tester) async {
    final locationSource = FakeLocationSource(permissionGranted: false);
    final container = ProviderContainer(
      overrides: [
        ..._baseOverrides(),
        locationSourceProvider.overrideWithValue(locationSource),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(MapScreen), findsOneWidget);
  });

  testWidgets('builds without throwing when the location source resolves a position', (tester) async {
    // MapLibreMap has no real platform view under flutter test, so
    // onMapCreated/onStyleLoadedCallback never fire and the camera-centering
    // / "my location" circle code path (which requires a live controller)
    // is never reached here -- that behavior is covered by manual device
    // verification, same precedent as long-press waypoint creation. This
    // test guards the wiring: fetching a resolved position must not throw
    // or leave the screen in a broken state.
    final locationSource = FakeLocationSource(currentPosition: const TrackPoint(lat: 45.9, lng: 7.6));
    final container = ProviderContainer(
      overrides: [
        ..._baseOverrides(),
        locationSourceProvider.overrideWithValue(locationSource),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(MapScreen), findsOneWidget);
  });
}
