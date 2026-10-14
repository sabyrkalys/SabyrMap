import 'package:app/map/screens/layer_look/layer_color_screen.dart';
import 'package:app/map/screens/layer_look/layer_color_tools_dialog.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../on_screen/harness.dart';
import 'look_harness.dart';

void main() {
  final h = LayersHarness();
  Future<void> open(WidgetTester tester) => pumpLook(tester, h, (c) => LayerColorScreen.show(c, 'yandex-hybrid'));
  RasterColor? mapColor() => h.host.colors[LayerManager.layerIdOf('yandex-hybrid')];

  testWidgets('title with the layer name; four sliders with their ends', (tester) async {
    await open(tester);
    expect(tester.widget<Text>(find.byKey(const Key('look_title'))).data, 'Изменить цвет · Яндекс Гибрид');
    for (final text in ['Контрастность: 100 %', 'Яркость: 100 %', 'Насыщенность: 100 %', 'Оттенок: 0 %']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('0 %'), findsNWidgets(3));
    expect(find.text('200 %'), findsNWidgets(3));
    expect(find.text('-100 %'), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);
  });

  testWidgets('a slider changes the layer settings and the map at once', (tester) async {
    await open(tester);
    sliderOf(tester, 'color_brightness').onChanged!(93);
    await tester.pumpAndSettle();
    expect(find.text('Яркость: 93 %'), findsOneWidget);
    expect(h.container.read(layerLooksProvider)['yandex-hybrid']!.color.brightness, closeTo(-0.07, 1e-9));
    expect(mapColor()!.brightnessMax, closeTo(0.93, 1e-9));

    sliderOf(tester, 'color_contrast').onChanged!(105);
    sliderOf(tester, 'color_saturation').onChanged!(0);
    sliderOf(tester, 'color_hue').onChanged!(-50);
    await tester.pumpAndSettle();
    final color = h.container.read(layerLooksProvider)['yandex-hybrid']!.color;
    expect(color.contrast, closeTo(1.05, 1e-9));
    expect(color.saturation, 0);
    expect(color.hue, -0.5);
    expect(mapColor()!.hueRotate, -90);
  });

  testWidgets('✓ closes the screen keeping the change', (tester) async {
    await open(tester);
    sliderOf(tester, 'color_saturation').onChanged!(150);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('look_done')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerColorScreen), findsNothing);
    expect(h.container.read(layerLooksProvider)['yandex-hybrid']!.color.saturation, 1.5);
  });

  testWidgets('the wrench opens «Инструменты»; ? shows a hint', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('look_help')));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.tap(find.byKey(const Key('look_tools')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerColorToolsDialog), findsOneWidget);
  });
}
