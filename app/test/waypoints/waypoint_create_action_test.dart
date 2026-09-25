import 'package:app/map/map_crosshair.dart';
import 'package:app/waypoints/waypoint_create_action.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'fakes.dart';

void main() {
  Future<ProviderContainer> pumpButton(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository())],
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

  testWidgets('with a crosshair position it opens the waypoint form', (tester) async {
    final container = await pumpButton(tester);
    container.read(mapCrosshairProvider.notifier).set(const LatLng(48, 37.8));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waypoint_name_field')), findsOneWidget);
  });
}
