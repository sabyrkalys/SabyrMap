import 'package:app/waypoints/waypoint_dialog/waypoint_data.dart';
import 'package:app/waypoints/waypoint_dialog/waypoint_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens the dialog from a button and records what it completes with.
  Future<List<WaypointData?>> open(WidgetTester tester, {String? pointLabel}) async {
    final results = <WaypointData?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(
                pointLabel == null
                    ? await showWaypointDialog(context)
                    : await showWaypointDialog(context, pointLabel: pointLabel),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> ok(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
    await tester.pumpAndSettle();
  }

  test('nextWaypointName numbers unnamed waypoints in order', () {
    expect(nextWaypointName(const []), 'Путевая точка 1');
    expect(
      nextWaypointName(const ['Родник', 'Путевая точка 1', 'Путевая точка 7', 'Путевая точка 3']),
      'Путевая точка 8',
    );
    expect(nextWaypointName(const ['Путевая точка', 'Путевая точка 2а']), 'Путевая точка 1');
  });

  testWidgets('layout: title, «Имя» focused, both dropdowns, four actions, ОТМЕНА and ОК', (tester) async {
    await open(tester);

    expect(find.text('Путевая точка'), findsOneWidget);
    expect(find.text('Имя'), findsOneWidget);
    final field = tester.widget<EditableText>(
      find.descendant(of: find.byKey(const Key('waypoint_dialog_name_field')), matching: find.byType(EditableText)),
    );
    expect(field.focusNode.hasFocus, isTrue);
    expect(find.text('Координаты центра экрана'), findsOneWidget);
    expect(find.text('Несортированные метки'), findsOneWidget);
    for (final key in [
      'waypoint_dialog_icon',
      'waypoint_dialog_color',
      'waypoint_dialog_note',
      'waypoint_dialog_more',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.text('ЕЩЁ...'), findsOneWidget);
    expect(find.text('ОТМЕНА'), findsOneWidget);
    expect(find.text('ОК'), findsOneWidget);
  });

  testWidgets('«ОТМЕНА» returns null', (tester) async {
    final results = await open(tester);
    await tester.tap(find.byKey(const Key('waypoint_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waypoint_dialog')), findsNothing);
    expect(results, [null]);
  });

  testWidgets('«ОК» with an empty name is allowed and returns the defaults', (tester) async {
    final results = await open(tester);
    await ok(tester);

    final data = results.single!;
    expect(data.name, '');
    expect(data.coords, WaypointCoords.screenCenter);
    expect(data.groupId, WaypointData.unsortedGroupId);
    expect(data.iconId, isNull);
    expect(data.colorValue, isNull);
    expect(data.type, 'generic');
    expect(data.note, '');
  });

  testWidgets('«ОК» returns the name, the chosen point and the description', (tester) async {
    final results = await open(tester);
    await tester.enterText(find.byKey(const Key('waypoint_dialog_name_field')), '  Родник ');

    await tester.tap(find.byKey(const Key('waypoint_dialog_coords')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Указать точку на карте').last);
    await tester.pumpAndSettle();
    expect(find.text('Указать точку на карте'), findsOneWidget);

    await tester.tap(find.byKey(const Key('waypoint_dialog_note')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypoint_dialog_note_field')), 'Холодная вода');
    await tester.tap(find.byKey(const Key('waypoint_dialog_note_ok')));
    await tester.pumpAndSettle();
    await ok(tester);

    final data = results.single!;
    expect(data.name, 'Родник');
    expect(data.coords, WaypointCoords.customPoint);
    expect(data.note, 'Холодная вода');
  });

  testWidgets('the palette picks a colour and tints itself', (tester) async {
    final results = await open(tester);
    await tester.tap(find.byKey(const Key('waypoint_dialog_color')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_color_picker_select_button')));
    await tester.pumpAndSettle();
    await ok(tester);

    // The picker opens on the type's colour (generic #607D8B).
    expect(results.single!.colorValue, 0xFF607D8B);
    expect(results.single!.colorHex, '#607D8B');
  });

  testWidgets('«ЕЩЁ...» lists every extra over the dialog; ОТМЕНА closes only the sheet', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('waypoint_dialog_more')));
    await tester.pumpAndSettle();

    for (final label in [
      'Цвет',
      'Стиль',
      'Изображение',
      'Галерея',
      'Аудио',
      'Курс',
      'Сайт',
      'Ключевые слова',
      'Описание',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.byKey(const Key('waypoint_more_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waypoint_more_sheet')), findsNothing);
    expect(find.byKey(const Key('waypoint_dialog')), findsOneWidget);
  });

  testWidgets('«ЕЩЁ...» → «Стиль» sets the waypoint type', (tester) async {
    final results = await open(tester);
    await tester.tap(find.byKey(const Key('waypoint_dialog_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_more_style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_dialog_type_water')));
    await tester.pumpAndSettle();
    await ok(tester);

    expect(results.single!.type, 'water');
  });

  testWidgets('a stub extra closes the sheet and leaves the dialog as it was', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('waypoint_dialog_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_more_website')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waypoint_more_sheet')), findsNothing);
    expect(find.byKey(const Key('waypoint_dialog')), findsOneWidget);
  });

  testWidgets('for a target the first point option names the target', (tester) async {
    await open(tester, pointLabel: 'Координаты цели');
    expect(find.text('Координаты цели'), findsOneWidget);
    expect(find.text('Координаты центра экрана'), findsNothing);
  });

  testWidgets('the keyboard does not cover ОК', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.reset);
    await open(tester);

    final okBottom = tester.getBottomLeft(find.byKey(const Key('waypoint_dialog_ok'))).dy;
    expect(okBottom, lessThanOrEqualTo((1920 - 900) / 3));
  });
}
