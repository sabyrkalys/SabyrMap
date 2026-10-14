import 'package:app/map/screens/on_screen/layer_blending_sheet.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:app/maps/layer_stack/layer_blending.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../on_screen/harness.dart';
import 'look_harness.dart';

void main() {
  final h = LayersHarness();
  Future<void> open(WidgetTester tester) => pumpLook(tester, h, (c) => LayerBlendingSheet.show(c, 'yandex-hybrid'));

  testWidgets('six modes in the order of the menu; the current one is picked', (tester) async {
    await open(tester);
    final labels = ['Нормальный (по умолчанию)', 'Замена светлым', 'Экран', 'Перекрытие', 'Умножение', 'Затенение'];
    final ys = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
    expect(ys, [...ys]..sort());
    expect(tester.widget<RadioGroup<LayerBlending>>(find.byType(RadioGroup<LayerBlending>)).groupValue,
        LayerBlending.normal);
  });

  testWidgets('a choice sets the mode, closes the sheet and says which', (tester) async {
    await open(tester);
    await tester.tap(find.text('Затенение'));
    await tester.pumpAndSettle();
    expect(find.byType(LayerBlendingSheet), findsNothing);
    expect(h.container.read(layerLooksProvider)['yandex-hybrid']!.blending, LayerBlending.darken);
    expect(find.text('Режим: Затенение'), findsOneWidget);
  });

  testWidgets('ОТМЕНА closes the sheet', (tester) async {
    await open(tester);
    await tester.tap(find.text('ОТМЕНА'));
    await tester.pumpAndSettle();
    expect(find.byType(LayerBlendingSheet), findsNothing);
  });
}
