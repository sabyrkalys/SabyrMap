import 'dart:async';

import 'package:app/map/map_crosshair.dart';
import 'package:app/app/landmark_services_provider.dart';
import 'package:app/waypoints/waypoint_create_action.dart';
import 'package:app/waypoints/waypoint_edits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../landmarks/services/fixture.dart';

/// Records what was created instead of writing files; [pending] holds
/// the answer back when set.
class _RecordingEdits extends WaypointEdits {
  _RecordingEdits(super.services);

  final created = <({String name, double lat, double lng, String? folder})>[];
  Completer<String>? pending;

  @override
  Iterable<String> get names => created.map((c) => c.name);

  @override
  Future<String> create({
    required String name,
    required String type,
    required String note,
    required String? color,
    required double lat,
    required double lng,
    String? iconFileName,
    String? folder,
    Map<String, Object> extra = const {},
  }) {
    created.add((name: name, lat: lat, lng: lng, folder: folder));
    return pending?.future ?? Future.value('/m/w${created.length}.wpt');
  }
}

void main() {
  late ServicesFixture f;
  late _RecordingEdits repo;
  setUp(() async {
    f = await ServicesFixture.create();
    repo = _RecordingEdits(f.services);
  });
  tearDown(() => f.dispose());

  Future<ProviderContainer> pumpButton(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [waypointEditsProvider.overrideWithValue(repo)]);
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
    final container = await pumpButton(tester);
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
    final container = await pumpButton(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
      await tester.pumpAndSettle();
    }

    expect(repo.created.map((c) => c.name), ['Путевая точка 1', 'Путевая точка 2']);
  });

  testWidgets('coordinates typed in «Координаты» are where the waypoint is created', (tester) async {
    final container = await pumpButton(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_dialog_coords')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_dialog_coords_edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('coords_x_field')), '6181945');
    await tester.enterText(find.byKey(const Key('coords_y_field')), '7413188');
    await tester.tap(find.byKey(const Key('coords_ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
    await tester.pumpAndSettle();

    expect(repo.created.single.lat, closeTo(55.75222, 1e-5));
    expect(repo.created.single.lng, closeTo(37.61556, 1e-5));
  });

  testWidgets('a failure still shows its message after the widget that started it is gone', (tester) async {
    final pending = repo.pending = Completer<String>();
    final container = ProviderContainer(overrides: [waypointEditsProvider.overrideWithValue(repo)]);
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
    pending.completeError(const WaypointException('boom'));
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('«ОК» saves into the folder of the chosen group', (tester) async {
    final container = ProviderContainer(
      overrides: [
        waypointEditsProvider.overrideWithValue(repo),
        markerGroupFoldersProvider.overrideWithValue(
          const MarkerGroupFolders(unsorted: '/root/landmarks/imported', myMarkers: '/root/landmarks'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));
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

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
    await tester.pumpAndSettle();

    expect(repo.created.single.folder, '/root/landmarks/imported');
  });
}
