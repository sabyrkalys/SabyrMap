import 'package:app/map/screens/layer_look/erase_color_screen.dart';
import 'package:app/map/screens/layer_look/erase_color_tools_dialog.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../on_screen/harness.dart';
import 'look_harness.dart';

void main() {
  final h = LayersHarness();
  Future<void> open(WidgetTester tester) => pumpLook(tester, h, (c) => EraseColorScreen.show(c, 'yandex-hybrid'));
  String label(WidgetTester tester, String channel) =>
      tester.widget<Text>(find.byKey(Key('erase_label_$channel'))).textSpan!.toPlainText();

  testWidgets('title; r, g, b with low, centre and high around black by default; 0 and 255 at the ends', (tester) async {
    await open(tester);
    expect(tester.widget<Text>(find.byKey(const Key('look_title'))).data, 'Удалить цвет · Яндекс Гибрид');
    expect(label(tester, 'r'), 'r: 0 0 5');
    expect(label(tester, 'g'), 'g: 0 0 5');
    expect(label(tester, 'b'), 'b: 0 0 5');
    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('255'), findsNWidgets(3));
    expect(sliderOf(tester, 'erase_r').divisions, 255);
  });

  testWidgets('moving a centre turns erasing on with that colour; the range is centre ± width, kept in 0..255',
      (tester) async {
    await open(tester);
    sliderOf(tester, 'erase_r').onChanged!(58);
    sliderOf(tester, 'erase_g').onChanged!(21);
    await tester.pumpAndSettle();
    sliderOf(tester, 'erase_b').onChanged!(253);
    await tester.pumpAndSettle();
    expect(label(tester, 'r'), 'r: 53 58 63');
    expect(label(tester, 'g'), 'g: 16 21 26');
    expect(label(tester, 'b'), 'b: 248 253 255');
    final erase = h.container.read(layerLooksProvider)['yandex-hybrid']!.erase;
    expect(erase.enabled, isTrue);
    expect(erase.ranges.map((r) => r.center), [58, 21, 253]);
  });

  testWidgets('✓ closes; the wrench opens the tools', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('look_tools')));
    await tester.pumpAndSettle();
    expect(find.byType(EraseColorToolsDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('erase_tools_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('look_done')));
    await tester.pumpAndSettle();
    expect(find.byType(EraseColorScreen), findsNothing);
  });
}
