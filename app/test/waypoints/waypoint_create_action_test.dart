import 'dart:async';

import 'package:app/map/map_crosshair.dart';
import 'package:app/waypoints/waypoint_create_action.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:app/waypoints/waypoints_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'fakes.dart';

class _SlowWaypointsRepository extends FakeWaypointsRepository {
  final pending = Completer<Waypoint>();

  @override
  Future<Waypoint> create({
    required String name,
    required String type,
    required String note,
    required String? color,
    required double lat,
    required double lng,
  }) =>
      pending.future;
}

/// Records what was created and answers with it.
class _RecordingWaypointsRepository extends FakeWaypointsRepository {
  final created = <({String name, double lat, double lng})>[];

  @override
  Future<Waypoint> create({
    required String name,
    required String type,
    required String note,
    required String? color,
    required double lat,
    required double lng,
  }) async {
    created.add((name: name, lat: lat, lng: lng));
    return Waypoint(
      id: 'w${created.length}',
      orgId: 'o',
      ownerId: 'u',
      name: name,
      type: type,
      note: note.isEmpty ? null : note,
      lat: lat,
      lng: lng,
      color: color,
      canEdit: true,
      createdAt: DateTime.utc(2026, 10, 8),
    );
  }
}

void main() {
  Future<ProviderContainer> pumpButton(WidgetTester tester, {WaypointsRepository? repo}) async {
    final container = ProviderContainer(
      overrides: [waypointsRepositoryProvider.overrideWithValue(repo ?? FakeWaypointsRepository())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => createWaypointAtCrosshair(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('before the map has settled it reports the map is not ready', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('Карта ещё не готова'), findsOneWidget);
  });

  testWidgets('with a crosshair position it opens the «Путевая точка» dialog', (tester) async {
    final container = await pumpButton(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypoint_dialog')), findsOneWidget);
  });

  testWidgets('«ОК» creates the waypoint at the crosshair with what was entered', (tester) async {
    final repo = _RecordingWaypointsRepository();
    final container = await pumpButton(tester, repo: repo);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypoint_dialog_name_field')), 'Родник');
    await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
    await tester.pumpAndSettle();

    expect(repo.created.single.name, 'Родник');
    expect(repo.created.single.lat, closeTo(48, 1e-9));
    expect(repo.created.single.lng, closeTo(37.8, 1e-9));
  });

  testWidgets('unnamed waypoints become «Путевая точка 1», «Путевая точка 2», …', (tester) async {
    final repo = _RecordingWaypointsRepository();
    final container = await pumpButton(tester, repo: repo);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
      await tester.pumpAndSettle();
    }

    expect(repo.created.map((c) => c.name), ['Путевая точка 1', 'Путевая точка 2']);
  });

  testWidgets('«Указать точку на карте» waits for a tap instead of creating at once', (tester) async {
    final repo = _RecordingWaypointsRepository();
    final container = await pumpButton(tester, repo: repo);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypoint_dialog_name_field')), 'Там');
    await tester.tap(find.byKey(const Key('waypoint_dialog_coords')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Указать точку на карте').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
    await tester.pumpAndSettle();

    expect(repo.created, isEmpty);
    expect(container.read(waypointPlacementProvider)?.name, 'Там');
  });

  testWidgets('a failure still shows its message after the widget that started it is gone', (tester) async {
    final repo = _SlowWaypointsRepository();
    final container = ProviderContainer(overrides: [waypointsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));
    var showButton = true;
    late StateSetter setHostState;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                if (!showButton) return const SizedBox.shrink();
                return Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () => createWaypointAtCrosshair(context, ref),
                    child: const Text('go'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypoint_dialog_name_field')), 'Summit');
    await tester.pump();
    await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
    await tester.pumpAndSettle();

    // The panel that started the action closes while the request is in flight.
    setHostState(() => showButton = false);
    await tester.pump();
    repo.pending.completeError(const WaypointException('boom'));
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);
  });
}
