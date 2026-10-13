import 'package:app/map/screens/on_screen/layer_opacity_sheet.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  final h = LayersHarness();

  Future<Slider> open(WidgetTester tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await tester.tap(find.byKey(const Key('layer_opacity_yandex-hybrid')));
    await tester.pumpAndSettle();
    return tester.widget<Slider>(find.byKey(const Key('opacity_slider')));
  }

  testWidgets('starts at the current opacity, with 0 % and 100 % marks', (tester) async {
    final slider = await open(tester);
    expect(slider.value, 75);
    expect(find.text('Непрозрачность · Яндекс Гибрид'), findsOneWidget);
    expect(find.text('0 %'), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);
    expect(find.text('75 %'), findsOneWidget);
  });

  testWidgets('dragging changes the map at once; letting go stores the value', (tester) async {
    final slider = await open(tester);
    slider.onChanged!(40);
    await tester.pumpAndSettle();
    expect(h.host.opacities[LayerManager.layerIdOf('yandex-hybrid')], 0.4);
    expect(find.text('40 %'), findsOneWidget);
    slider.onChangeEnd!(40);
    await tester.pumpAndSettle();
    expect(h.state.overlays.single.opacity, 0.4);
    expect(h.store.saved!.overlays.single.opacity, 0.4);
    await tester.tap(find.byKey(const Key('opacity_done')));
    await tester.pumpAndSettle();
    expect(find.text('40 % непрозрачн.'), findsOneWidget);
  });

  testWidgets('the tick closes the sheet', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('opacity_done')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerOpacitySheet), findsNothing);
  });
}
