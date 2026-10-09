import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/waypoints/waypoint_color_picker.dart';

void main() {
  Future<WaypointColorPick? Function()> open(WidgetTester tester, Color initial) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    WaypointColorPick? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showWaypointColorPicker(context, initial);
              closed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return () => closed ? result : throw StateError('still open');
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('OK without touching anything gives back the very same colour', (tester) async {
    final result = await open(tester, const Color(0xFF607D8B));
    expect(find.text('Цвет'), findsOneWidget);
    expect(find.text('100 % непрозрачн.'), findsOneWidget);
    await tapText(tester, 'OK');
    expect(result(), (reset: false, color: const Color(0xFF607D8B)));
  });

  testWidgets('a ready colour keeps the opacity set on the slider', (tester) async {
    final result = await open(tester, const Color(0xFF607D8B));
    final slider = find.byKey(const Key('waypoint_color_picker_opacity'));
    await tester.tapAt(tester.getCenter(slider));
    await tester.pumpAndSettle();
    expect(find.text('50 % непрозрачн.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('waypoint_color_preset_3')));
    await tester.pumpAndSettle();
    await tapText(tester, 'OK');
    final color = result()!.color;
    expect(color.withAlpha(255), waypointPresetColors[3]);
    expect((color.a * 100).round(), 50);
  });

  testWidgets('the plane and the hue bar move the colour', (tester) async {
    final result = await open(tester, const Color(0xFFFF0000));
    final plane = find.byKey(const Key('waypoint_color_picker_plane'));
    await tester.tapAt(tester.getBottomLeft(plane) + const Offset(1, -1));
    await tester.pumpAndSettle();
    await tapText(tester, 'OK');
    final dark = HSVColor.fromColor(result()!.color);
    expect(dark.value, lessThan(0.05));
  });

  testWidgets('the hue bar runs from red at the top through blue to red at the bottom', (tester) async {
    final result = await open(tester, const Color(0xFFFF0000));
    final hue = find.byKey(const Key('waypoint_color_picker_hue'));
    final rect = tester.getRect(hue);
    // A third of the way down: 240°, blue.
    await tester.tapAt(Offset(rect.center.dx, rect.top + rect.height / 3));
    await tester.pumpAndSettle();
    await tapText(tester, 'OK');
    expect(HSVColor.fromColor(result()!.color).hue, closeTo(240, 3));
  });

  testWidgets('СБРОСИТЬ resets, ОТМЕНА gives nothing', (tester) async {
    var result = await open(tester, const Color(0xFF607D8B));
    await tapText(tester, 'СБРОСИТЬ');
    expect(result()!.reset, isTrue);

    result = await open(tester, const Color(0xFF607D8B));
    await tapText(tester, 'ОТМЕНА');
    expect(result(), isNull);
  });
}
