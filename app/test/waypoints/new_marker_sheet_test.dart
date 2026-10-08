import 'package:app/waypoints/new_marker/marker_type.dart';
import 'package:app/waypoints/new_marker/marker_type_item.dart';
import 'package:app/waypoints/new_marker/new_marker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens the sheet from a button and records what it completes with.
  Future<List<MarkerType?>> open(WidgetTester tester) async {
    final results = <MarkerType?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(await showNewMarkerSheet(context)),
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

  Future<void> scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(of: find.byKey(const Key('new_marker_sheet')), matching: find.byType(Scrollable)),
  );

  test('17 types: 9 local marks, then 8 tools', () {
    expect(markerTypes.where((t) => t.category == MarkerCategory.local).map((t) => t.title), [
      'Путевая точка',
      'Фототочка',
      'Аудиоточка',
      'Набор точек',
      'Маршрут',
      'Путь',
      'Область',
      'Круг',
      'Текст',
    ]);
    expect(markerTypes.where((t) => t.category == MarkerCategory.tool).map((t) => t.title), [
      'Поиск на карте',
      'Поиск по имени',
      'Спроектировать местоположение',
      'Автомаршрутизация',
      'Быстрая маршрутизация',
      'Измерение',
      'Уклон',
      'Оповещение о сближении',
    ]);
    expect(markerTypes.map((t) => t.id).toSet(), hasLength(markerTypes.length));
  });

  testWidgets('title, both sections in order, subtitles only where given', (tester) async {
    await open(tester);

    expect(find.text('Новая метка'), findsOneWidget);
    expect(find.text('ЛОКАЛЬНЫЕ МЕТКИ'), findsOneWidget);
    expect(find.text('Создать путевую точку на карте.'), findsOneWidget);
    final photoRow = find.byKey(const Key('marker_type_photo'));
    expect(find.descendant(of: photoRow, matching: find.byType(Text)), findsOneWidget);

    await scrollTo(tester, find.text('ИНСТРУМЕНТЫ'));
    expect(
      tester.getTopLeft(find.text('ИНСТРУМЕНТЫ')).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('marker_type_text'))).dy),
    );
  });

  testWidgets('every row looks the same: one icon colour, nothing disabled', (tester) async {
    await open(tester);
    final colors = tester.widgetList<Icon>(
      find.descendant(of: find.byType(MarkerTypeItem), matching: find.byType(Icon)),
    );
    expect(colors.map((i) => i.color).toSet(), {MarkerTypeItem.iconColor});
    for (final item in tester.widgetList<InkWell>(
      find.descendant(of: find.byType(MarkerTypeItem), matching: find.byType(InkWell)),
    )) {
      expect(item.onTap, isNotNull);
    }
  });

  testWidgets('a tap on a row closes the sheet with that type', (tester) async {
    final results = await open(tester);
    await tester.tap(find.text('Путевая точка'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_marker_sheet')), findsNothing);
    expect(results.single?.id, MarkerTypeIds.waypoint);
  });

  testWidgets('the list scrolls down to the last tool', (tester) async {
    tester.view.physicalSize = const Size(1080, 1600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final results = await open(tester);

    await scrollTo(tester, find.text('Оповещение о сближении'));
    await tester.tap(find.text('Оповещение о сближении'));
    await tester.pumpAndSettle();
    expect(results.single?.id, 'proximity_alert');
  });

  testWidgets('«ОТМЕНА» closes the sheet with null', (tester) async {
    final results = await open(tester);
    await scrollTo(tester, find.byKey(const Key('new_marker_cancel')));
    final cancel = tester.widget<TextButton>(find.byKey(const Key('new_marker_cancel')));
    expect(cancel.style!.foregroundColor!.resolve({}), NewMarkerSheet.cancelColor);

    await tester.tap(find.byKey(const Key('new_marker_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new_marker_sheet')), findsNothing);
    expect(results, [null]);
  });

  testWidgets('the rows come from the list it is given', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NewMarkerSheet(
            onMarkerTypeSelected: (_) {},
            types: const [
              MarkerType(id: 'a', title: 'Одна', icon: Icons.star, category: MarkerCategory.local),
              MarkerType(id: 'b', title: 'Другая', icon: Icons.star, category: MarkerCategory.tool),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(MarkerTypeItem), findsNWidgets(2));
    expect(find.text('Путевая точка'), findsNothing);
  });
}
