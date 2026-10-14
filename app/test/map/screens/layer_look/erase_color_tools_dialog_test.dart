import 'package:app/map/screens/layer_look/erase_color_range_dialog.dart';
import 'package:app/map/screens/layer_look/erase_color_screen.dart';
import 'package:app/map/screens/layer_look/erase_color_settings_providers.dart';
import 'package:app/map/screens/layer_look/erase_color_tools_dialog.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:app/maps/color/erase_color_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../on_screen/harness.dart';
import 'look_harness.dart';

void main() {
  final h = LayersHarness();

  Future<void> openTools(WidgetTester tester, {int? pixel}) async {
    await pumpLook(
      tester,
      h,
      (c) => EraseColorScreen.show(c, 'yandex-hybrid'),
      overrides: [centerPixelProvider.overrideWithValue(() async => pixel)],
    );
    await tester.tap(find.byKey(const Key('look_tools')));
    await tester.pumpAndSettle();
  }

  EraseColorSettings erase() => h.container.read(layerLooksProvider)['yandex-hybrid']!.erase;

  testWidgets('title and both items', (tester) async {
    await openTools(tester);
    expect(find.text('Удалить цвет'), findsOneWidget);
    expect(find.text('Для удаления использовать цвет под центром экрана'), findsOneWidget);
    expect(find.text('Диапазон удаления'), findsOneWidget);
  });

  testWidgets('the colour under the crosshair sets all three centres', (tester) async {
    await openTools(tester, pixel: 0xFF3A152D);
    await tester.tap(find.byKey(const Key('erase_tools_center')));
    await tester.pumpAndSettle();
    expect(find.byType(EraseColorToolsDialog), findsNothing);
    expect(erase().ranges.map((r) => r.center), [0x3A, 0x15, 0x2D]);
    expect(erase().enabled, isTrue);
    expect(find.text('Цвет взят из-под прицела'), findsOneWidget);
  });

  testWidgets('no colour under the crosshair: «Цвет недоступен», nothing changes', (tester) async {
    await openTools(tester);
    await tester.tap(find.byKey(const Key('erase_tools_center')));
    await tester.pumpAndSettle();
    expect(find.text('Цвет недоступен'), findsOneWidget);
    expect(h.container.read(layerLooksProvider)['yandex-hybrid'], isNull);
  });

  testWidgets('«Диапазон удаления» opens its dialog instead', (tester) async {
    await openTools(tester);
    await tester.tap(find.byKey(const Key('erase_tools_range')));
    await tester.pumpAndSettle();
    expect(find.byType(EraseColorToolsDialog), findsNothing);
    expect(find.byType(EraseColorRangeDialog), findsOneWidget);
  });

  testWidgets('СБРОСИТЬ: empty settings and a message; ОТМЕНА just closes', (tester) async {
    await openTools(tester, pixel: 0xFFFFFFFF);
    await tester.tap(find.byKey(const Key('erase_tools_center')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('look_tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('erase_tools_reset')));
    await tester.pumpAndSettle();
    expect(erase(), EraseColorSettings.empty());
    expect(find.text('Настройки удаления цвета сброшены'), findsOneWidget);

    await tester.tap(find.byKey(const Key('look_tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('erase_tools_cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(EraseColorToolsDialog), findsNothing);
    expect(erase(), EraseColorSettings.empty());
  });
}
