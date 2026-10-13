import 'package:app/map/screens/compare/compare_select_dialog.dart';
import 'package:app/map/screens/on_screen/layer_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../on_screen/harness.dart';

void main() {
  final h = LayersHarness();
  List<String>? result;
  var closed = false;

  Future<void> open(WidgetTester tester, String sourceId) async {
    result = null;
    closed = false;
    await h.pump(
      tester,
      saved: stateWith(const [hybridLayer, osmLayer]),
      child: Builder(
        builder: (context) => TextButton(
          key: const Key('open_compare'),
          onPressed: () async {
            result = await CompareSelectDialog.show(context, sourceId);
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_compare')));
    await tester.pumpAndSettle();
  }

  bool checked(WidgetTester tester, String id) => tester
      .widget<Checkbox>(find.descendant(of: find.byKey(Key('compare_select_$id')), matching: find.byType(Checkbox)))
      .value!;

  testWidgets('every layer top → bottom and the base map; no orthophotos; only the source is ticked', (tester) async {
    await open(tester, 'yandex-hybrid');
    expect(find.text('Сравнить...'), findsOneWidget);
    final osmY = tester.getTopLeft(find.text('OSM Standard Raster')).dy;
    final hybridY = tester.getTopLeft(find.text('Яндекс Гибрид')).dy;
    final baseY = tester.getTopLeft(find.text('OpenFreeMap Liberty (базовая)')).dy;
    expect(osmY < hybridY && hybridY < baseY, isTrue);
    expect(find.text('Ортофотопланы'), findsNothing);
    expect(checked(tester, 'yandex-hybrid'), isTrue);
    expect(checked(tester, 'osm-standard'), isFalse);
    expect(checked(tester, LayerContextMenu.baseId), isFalse);
  });

  testWidgets('ОК with one layer says so and stays open', (tester) async {
    await open(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('compare_select_ok')));
    await tester.pumpAndSettle();
    expect(find.text('Выберите хотя бы 2 слоя'), findsOneWidget);
    expect(find.byType(CompareSelectDialog), findsOneWidget);
    expect(closed, isFalse);
  });

  testWidgets('ОК with two or more returns their ids top → bottom', (tester) async {
    await open(tester, 'yandex-hybrid');
    await tester.tap(find.text('OpenFreeMap Liberty (базовая)'));
    await tester.tap(find.text('OSM Standard Raster'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('compare_select_ok')));
    await tester.pumpAndSettle();
    expect(find.byType(CompareSelectDialog), findsNothing);
    expect(result, ['osm-standard', 'yandex-hybrid', LayerContextMenu.baseId]);
  });

  testWidgets('ОТМЕНА returns null', (tester) async {
    await open(tester, 'yandex-hybrid');
    await tester.tap(find.text('ОТМЕНА'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });
}
