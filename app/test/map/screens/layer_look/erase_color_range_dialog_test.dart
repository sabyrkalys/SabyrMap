import 'package:app/map/screens/layer_look/erase_color_range_dialog.dart';
import 'package:app/map/screens/layer_look/erase_color_screen.dart';
import 'package:app/map/screens/layer_look/erase_color_settings_providers.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../on_screen/harness.dart';
import 'look_harness.dart';

void main() {
  final h = LayersHarness();

  Future<void> openRange(WidgetTester tester) async {
    await pumpLook(tester, h, (c) => EraseColorScreen.show(c, 'yandex-hybrid'));
    sliderOf(tester, 'erase_r').onChanged!(58);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('look_tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('erase_tools_range')));
    await tester.pumpAndSettle();
  }

  testWidgets('six widths; the current one (±5) is picked', (tester) async {
    await openRange(tester);
    for (final w in ['±1', '±3', '±5', '±9', '±15', '±23']) {
      expect(find.text(w), findsOneWidget, reason: w);
    }
    expect(tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue, 5);
  });

  testWidgets('a choice is applied, remembered and closes the dialog', (tester) async {
    await openRange(tester);
    await tester.tap(find.byKey(const Key('erase_range_15')));
    await tester.pumpAndSettle();
    expect(find.byType(EraseColorRangeDialog), findsNothing);
    expect(h.container.read(colorRangesWidthProvider), 15);
    expect(h.container.read(layerLooksProvider)['yandex-hybrid']!.erase.ranges.map((r) => r.width), [15, 15, 15]);
    expect(tester.widget<Text>(find.byKey(const Key('erase_label_r'))).textSpan!.toPlainText(), 'r: 43 58 73');
    expect(find.text('Диапазон: ±15'), findsOneWidget);
  });

  testWidgets('ОТМЕНА returns null and changes nothing', (tester) async {
    int? result = -1;
    await pumpLook(tester, h, (c) async => result = await EraseColorRangeDialog.show(c, 'yandex-hybrid'));
    await tester.tap(find.byKey(const Key('erase_range_cancel')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(h.container.read(colorRangesWidthProvider), 5);
  });
}
