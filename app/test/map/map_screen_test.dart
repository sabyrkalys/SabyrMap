import 'package:app/icons/waypoint_icon_assignments_controller.dart';
import 'package:app/icons/waypoint_icon_store.dart';
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
import 'dart:math' show Point;

import 'package:app/waypoints/waypoint_create_action.dart';
import 'package:app/waypoints/waypoint_dialog/waypoint_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Offset screenCenter(WidgetTester tester) => tester.getCenter(find.byType(MapLibreMap));

  Future<ProviderContainer> pumpMap(WidgetTester tester, {FakeWaypointsRepository? waypointsRepo}) async {
    final container = ProviderContainer(overrides: _baseOverrides(waypointsRepo: waypointsRepo));
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

  testWidgets('«Задать цель» makes the point under the crosshair the target, right away', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Задать цель'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
    expect(container.read(mapTargetProvider).point, const LatLng(48, 37.8));
    expect(find.textContaining('Коснитесь карты'), findsNothing);
    expect(find.text('0,0 м'), findsOneWidget);
  });

  testWidgets('the target line and dot are handed to the native map; «Линия к цели» off hides them', (tester) async {
    final calls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('sabyrmap/map'), (call) async {
      if (call.method == 'setTarget') calls.add(call.arguments);
      return 1;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('sabyrmap/map'), null),
    );
    final container = await pumpMap(tester);

    container.read(mapTargetProvider.notifier).setAt(const LatLng(48.1, 37.8));
    await tester.pump();
    expect(calls.last, {'lat': closeTo(48.1, 1e-9), 'lng': closeTo(37.8, 1e-9)});

    container.read(menuTogglesProvider.notifier).set(MenuToggle.waypointsTargetLine, false);
    await tester.pump();
    expect(calls.last, isEmpty);

    container.read(menuTogglesProvider.notifier).set(MenuToggle.waypointsTargetLine, true);
    await tester.pump();
    expect(calls.last, {'lat': closeTo(48.1, 1e-9), 'lng': closeTo(37.8, 1e-9)});

    container.read(mapTargetProvider.notifier).clear();
    await tester.pump();
    expect(calls.last, isEmpty);
  });

  testWidgets('with a target the crosshair opens «Убрать цель» / «Путевая точка»; «Убрать цель» resets it', (
    tester,
  ) async {
    final container = await pumpMap(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));
    container.read(mapTargetProvider.notifier).setAt(const LatLng(48.1, 37.8));
    await tester.pump();

    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();
    expect(find.text('Путевая точка'), findsOneWidget);
    expect(find.text('Задать цель'), findsNothing);

    await tester.tap(find.text('Убрать цель'));
    await tester.pumpAndSettle();
    expect(container.read(mapTargetProvider), isA<MapTargetNone>());
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
    expect(find.byKey(const Key('target_distance_label')), findsNothing);
  });

  testWidgets('«Путевая точка» opens the waypoint dialog for the target and keeps the target', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));
    container.read(mapTargetProvider.notifier).setAt(const LatLng(48.1, 37.8));
    await tester.pump();

    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Путевая точка'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
    expect(find.byKey(const Key('waypoint_dialog')), findsOneWidget);
    expect(find.text('Координаты цели'), findsOneWidget);
    expect(container.read(mapTargetProvider).point, const LatLng(48.1, 37.8));
  });

  testWidgets('«Задать цель» before the map has settled reports the map is not ready', (tester) async {
    final container = await pumpMap(tester);
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Задать цель'));
    await tester.pumpAndSettle();
    expect(find.text('Карта ещё не готова'), findsOneWidget);
    expect(container.read(mapTargetProvider), isA<MapTargetNone>());
  });

  testWidgets('a map tap places a waypoint that waits for its point, and only then', (tester) async {
    final repo = FakeWaypointsRepository()
      ..createResult = Waypoint(
        id: 'w1',
        orgId: 'o1',
        ownerId: 'u1',
        name: 'Там',
        type: 'generic',
        note: null,
        lat: 48.1,
        lng: 37.8,
        canEdit: true,
        createdAt: DateTime.utc(2026, 10, 8),
      );
    final container = await pumpMap(tester, waypointsRepo: repo);
    void tapMap(LatLng at) => tester.widget<MapLibreMap>(find.byType(MapLibreMap)).onMapClick!(const Point(0, 0), at);

    tapMap(const LatLng(48.1, 37.8));
    await tester.pump();
    expect(container.read(waypointsControllerProvider), isEmpty);

    container.read(waypointPlacementProvider.notifier).start(const WaypointData(name: 'Там'));
    await tester.pump();
    expect(find.byKey(const Key('waypoint_placement_hint')), findsOneWidget);
    // A tap on the crosshair goes to the map, not to the card.
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);

    tapMap(const LatLng(48.1, 37.8));
    await tester.pumpAndSettle();
    expect(container.read(waypointsControllerProvider).single.name, 'Там');
    expect(container.read(waypointPlacementProvider), isNull);
    expect(find.byKey(const Key('waypoint_placement_hint')), findsNothing);
  });

  testWidgets('«Отмена» on the placement hint drops the waiting waypoint', (tester) async {
    final container = await pumpMap(tester);
    container.read(waypointPlacementProvider.notifier).start(const WaypointData(name: 'Там'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('waypoint_placement_cancel')));
    await tester.pump();
    expect(container.read(waypointPlacementProvider), isNull);
    expect(find.byKey(const Key('waypoint_placement_hint')), findsNothing);
  });

  testWidgets('the crosshair is a white 8 dp dot in a 2 dp dark border', (tester) async {
    await pumpMap(tester);
    final dot = tester.widget<Container>(find.byKey(const Key('map_crosshair')));
    final decoration = dot.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    final border = decoration.border! as Border;
    expect(border.top.width, 2);
    expect(border.top.color, Theme.of(tester.element(find.byKey(const Key('map_crosshair')))).colorScheme.onSurface);
    expect(tester.getSize(find.byKey(const Key('map_crosshair'))), const Size(12, 12));
  });

  testWidgets('distance label follows «Статус цели»', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));
    container.read(mapTargetProvider.notifier).setAt(const LatLng(48, 37.8));
    await tester.pump();
    expect(find.byKey(const Key('target_distance_label')), findsOneWidget);
    expect(find.text('0,0 м'), findsOneWidget);

    container.read(menuTogglesProvider.notifier).set(MenuToggle.waypointsTargetStatus, false);
    await tester.pump();
    expect(find.byKey(const Key('target_distance_label')), findsNothing);
  });

  testWidgets('the distance plate sits at a fixed spot right of the crosshair', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));
    container.read(mapTargetProvider.notifier).setAt(const LatLng(48.5, 38.5));
    await tester.pump();

    final plate = find.byKey(const Key('target_distance_label'));
    final crosshair = find.byKey(const Key('map_crosshair'));
    expect(tester.getCenter(plate).dy, closeTo(tester.getCenter(crosshair).dy, 0.5));
    expect(tester.getTopLeft(plate).dx, greaterThanOrEqualTo(tester.getTopRight(crosshair).dx));
  });

  testWidgets('«Новая метка...» opens the «Новая метка» sheet; «ОТМЕНА» does nothing else', (tester) async {
    await pumpMap(tester);
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Новая метка...'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
    expect(find.byKey(const Key('new_marker_sheet')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('new_marker_cancel')),
      200,
      scrollable: find.descendant(of: find.byKey(const Key('new_marker_sheet')), matching: find.byType(Scrollable)),
    );
    await tester.tap(find.byKey(const Key('new_marker_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new_marker_sheet')), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('«Путевая точка» in the sheet goes on to the waypoint form (map not ready yet here)', (tester) async {
    await pumpMap(tester);
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая метка...'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Путевая точка'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new_marker_sheet')), findsNothing);
    expect(find.text('Карта ещё не готова'), findsOneWidget);
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
    container.read(mapTargetProvider.notifier).setAt(const LatLng(48, 37.8));
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

  testWidgets('the map is capped at zoom 22 and the old coordinate HUD is gone', (tester) async {
    await pumpMap(tester);
    final map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));
    expect(map.minMaxZoomPreference.maxZoom, 22);
    expect(find.byKey(const Key('coordinate_hud')), findsNothing);
  });

  testWidgets('«i» opens the ИНФОРМАЦИЯ sheet for the point under the crosshair', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(47.9958, 37.81465));
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('crosshair_menu_info')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crosshair_menu')), findsNothing);
    expect(find.text('ИНФОРМАЦИЯ'), findsOneWidget);
    expect(find.text('47.99580, 37.81465'), findsOneWidget);
  });

  testWidgets('«i» before the map has settled reports the map is not ready', (tester) async {
    await pumpMap(tester);
    await tester.tapAt(screenCenter(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('crosshair_menu_info')));
    await tester.pumpAndSettle();
    expect(find.text('Карта ещё не готова'), findsOneWidget);
    expect(find.text('ИНФОРМАЦИЯ'), findsNothing);
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
