import 'package:app/icons/waypoint_icon_assignments_controller.dart';
import 'package:app/icons/waypoint_icon_store.dart';
import 'package:app/map/map_screen.dart';
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

  testWidgets('shows a persistent crosshair and a create-waypoint button, with no long-press wiring', (tester) async {
    final container = ProviderContainer(
      overrides: _baseOverrides(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('map_crosshair')), findsOneWidget);
    expect(find.byKey(const Key('create_waypoint_button')), findsOneWidget);

    final map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));
    expect(map.onMapLongClick, isNull);
  });

  testWidgets('tapping create-waypoint button before the map controller is ready shows a message, no crash', (tester) async {
    final container = ProviderContainer(
      overrides: _baseOverrides(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    // MapLibreMap has no real platform view under flutter test, so
    // onMapCreated never fires and _controller stays null -- this exercises
    // the FAB's fallback path (real crosshair-driven creation is covered by
    // manual device verification, same precedent as the old long-press flow
    // it replaces).
    await tester.tap(find.byKey(const Key('create_waypoint_button')));
    await tester.pumpAndSettle();

    expect(find.text('Карта ещё не готова'), findsOneWidget);
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
