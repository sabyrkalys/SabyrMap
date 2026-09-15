import 'dart:async';

import 'package:app/compass/compass_screen.dart';
import 'package:app/compass/compass_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('cardinalLabel maps headings to the nearest compass point', () {
    expect(cardinalLabel(0), 'С');
    expect(cardinalLabel(22), 'С');
    expect(cardinalLabel(24), 'СВ');
    expect(cardinalLabel(90), 'В');
    expect(cardinalLabel(180), 'Ю');
    expect(cardinalLabel(270), 'З');
    expect(cardinalLabel(359), 'С');
  });

  testWidgets('shows an unavailable message when there is no compass sensor', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource())],
        child: const MaterialApp(home: CompassScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Компас недоступен на этом устройстве'), findsOneWidget);
  });

  testWidgets('shows the heading and cardinal label once the sensor emits', (tester) async {
    final controller = StreamController<double?>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [compassSourceProvider.overrideWithValue(FakeCompassSource(controller.stream))],
        child: const MaterialApp(home: CompassScreen()),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('compass_loading')), findsOneWidget);

    controller.add(90);
    await tester.pump();

    expect(find.text('90° В'), findsOneWidget);
  });
}
