import 'package:app/map/crosshair_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tools = [
    'Поиск на карте (по имени)',
    'Спроектировать местоположение',
    'Автомаршрутизация',
    'Измерение',
    'Уклон',
    'Оповещение о сближении',
    'Поделиться',
  ];

  Future<List<String>> pump(WidgetTester tester, {bool hasTarget = false}) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CrosshairMenu(
              hasTarget: hasTarget,
              onSetTarget: () => calls.add('set'),
              onRemoveTarget: () => calls.add('remove'),
              onNewWaypoint: () => calls.add('new'),
              onInfo: () => calls.add('info'),
            ),
          ),
        ),
      ),
    );
    return calls;
  }

  double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

  testWidgets('icon row on top, then the three items in order', (tester) async {
    await pump(tester);

    final pin = find.byKey(const Key('crosshair_menu_pin'));
    expect(pin, findsOneWidget);
    expect(find.byKey(const Key('crosshair_menu_camera')), findsOneWidget);
    expect(find.byKey(const Key('crosshair_menu_info')), findsOneWidget);
    expect(top(tester, pin), lessThan(top(tester, find.text('Задать цель'))));
    expect(top(tester, find.text('Задать цель')), lessThan(top(tester, find.text('Новая метка...'))));
    expect(top(tester, find.text('Новая метка...')), lessThan(top(tester, find.text('Инструменты...'))));
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('pin and camera are disabled placeholders', (tester) async {
    await pump(tester);
    for (final key in ['crosshair_menu_pin', 'crosshair_menu_camera']) {
      expect(tester.widget<IconButton>(find.byKey(Key(key))).onPressed, isNull, reason: key);
    }
  });

  testWidgets('items call their callbacks', (tester) async {
    final calls = await pump(tester);
    await tester.tap(find.text('Задать цель'));
    await tester.tap(find.text('Новая метка...'));
    expect(calls, ['set', 'new']);
  });

  testWidgets('with a target the first item is «Убрать цель»', (tester) async {
    final calls = await pump(tester, hasTarget: true);
    expect(find.text('Задать цель'), findsNothing);
    await tester.tap(find.text('Убрать цель'));
    expect(calls, ['remove']);
  });

  testWidgets('«Инструменты...» shows the tools list and back returns', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Инструменты...'));
    await tester.pumpAndSettle();

    for (final tool in tools) {
      expect(find.text(tool), findsOneWidget, reason: tool);
    }
    expect(find.text('Задать цель'), findsNothing);

    await tester.tap(find.byKey(const Key('crosshair_menu_tools_back')));
    await tester.pumpAndSettle();
    expect(find.text('Задать цель'), findsOneWidget);
    expect(find.text(tools.first), findsNothing);
  });

  testWidgets('triangle sits under the card, horizontally centred', (tester) async {
    await pump(tester);
    final card = find.byKey(const Key('crosshair_menu'));
    final triangle = find.byKey(const Key('crosshair_menu_triangle'));
    expect(tester.getSize(triangle), const Size(16, 8));
    expect(tester.getTopLeft(triangle).dy, tester.getBottomLeft(card).dy);
    expect(tester.getCenter(triangle).dx, tester.getCenter(card).dx);
    expect(tester.getSize(card).width, lessThanOrEqualTo(320));
  });

  testWidgets('info icon is active and calls back', (tester) async {
    final calls = await pump(tester);
    expect(tester.widget<IconButton>(find.byKey(const Key('crosshair_menu_info'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('crosshair_menu_info')));
    expect(calls, ['info']);
  });
}
