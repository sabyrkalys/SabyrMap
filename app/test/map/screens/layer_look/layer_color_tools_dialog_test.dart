import 'package:app/map/screens/layer_look/layer_color_screen.dart';
import 'package:app/map/screens/layer_look/layer_color_tools_dialog.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:app/maps/color/layer_color_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../on_screen/harness.dart';
import 'look_harness.dart';

void main() {
  final h = LayersHarness();

  Future<void> openTools(WidgetTester tester) async {
    await pumpLook(tester, h, (c) => LayerColorScreen.show(c, 'yandex-hybrid'));
    sliderOf(tester, 'color_contrast').onChanged!(150);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('look_tools')));
    await tester.pumpAndSettle();
  }

  LayerColorSettings color() => h.container.read(layerLooksProvider)['yandex-hybrid']?.color ?? const LayerColorSettings();

  testWidgets('title and the one checkbox; it toggles the inversion', (tester) async {
    await openTools(tester);
    expect(find.text('Инструменты'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('Инверсия цветов'), findsOneWidget);
    await tester.tap(find.byKey(const Key('color_tools_invert')));
    await tester.pumpAndSettle();
    expect(color().inverted, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('СБРОСИТЬ asks; confirming resets everything and closes both dialogs', (tester) async {
    await openTools(tester);
    await tester.tap(find.byKey(const Key('color_tools_invert')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('color_tools_reset')));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить настройки цвета?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('color_reset_ok')));
    await tester.pumpAndSettle();
    expect(color(), LayerColorSettings.identity());
    expect(find.byType(LayerColorToolsDialog), findsNothing);
    expect(find.byKey(const Key('color_reset_confirm')), findsNothing);
    expect(find.text('Настройки цвета сброшены'), findsOneWidget);
    expect(find.byType(LayerColorScreen), findsOneWidget, reason: 'the screen stays');
  });

  testWidgets('ОТМЕНА closes without changes', (tester) async {
    await openTools(tester);
    await tester.tap(find.byKey(const Key('color_tools_cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerColorToolsDialog), findsNothing);
    expect(color().contrast, 1.5);
  });
}
