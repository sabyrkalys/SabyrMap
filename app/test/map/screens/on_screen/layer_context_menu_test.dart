import 'package:app/map/screens/compare/compare_mode_screen.dart';
import 'package:app/map/screens/compare/compare_select_dialog.dart';
import 'package:app/map/screens/layer_details/layer_details_screen.dart';
import 'package:app/map/screens/layers_panel.dart';
import 'package:app/map/screens/on_screen/layer_blending_sheet.dart';
import 'package:app/map/screens/on_screen/layer_color_sheet.dart';
import 'package:app/map/screens/on_screen/layer_context_menu.dart';
import 'package:app/map/screens/on_screen/layer_erase_color_sheet.dart';
import 'package:app/map/screens/on_screen/layer_opacity_sheet.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:app/maps/layer_stack/layer_blending.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  final h = LayersHarness();

  Future<void> openMenu(WidgetTester tester, String sourceId) async {
    await tester.tap(find.byKey(Key('layer_menu_$sourceId')));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<InkWell>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(InkWell)).first).onTap != null;

  String layerId(String sourceId) => LayerManager.layerIdOf(sourceId);

  testWidgets('title is the layer name; every item is there', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    final menu = find.byType(LayerContextMenu);
    for (final text in [
      'Яндекс Гибрид',
      'Детали',
      'Сравнить...',
      'Принудительное обновление сохранённых фрагментов карты (только эта сессия)',
      'УПОРЯДОЧИТЬ',
      'Убрать',
      'Убрать остальные',
      'Переместить вниз',
      'ИЗМЕНИТЬ',
      'Для сохранения изменений создайте/обновите избранную карту или набор карт.',
      'Непрозрачность',
      'Изменить цвет',
      'Удалить цвет',
      'Режим смешивания слоёв',
      'Инверсия цветов',
      'ОТМЕНА',
    ]) {
      expect(find.descendant(of: menu, matching: find.text(text)), findsOneWidget, reason: text);
    }
  });

  testWidgets('«Убрать» removes the layer and closes the menu', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_remove')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerContextMenu), findsNothing);
    expect(h.state.overlays, isEmpty);
    expect(h.host.layers, isNot(contains(layerId('yandex-hybrid'))));
  });

  testWidgets('«Убрать остальные» asks first, then keeps only this layer', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer, osmLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_remove_others')));
    await tester.pumpAndSettle();
    expect(find.text('Убрать остальные слои?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(h.state.overlays.map((l) => l.sourceId), ['yandex-hybrid']);
  });

  testWidgets('for the base map «Убрать остальные» removes nothing and says why', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'base');
    expect(enabled(tester, 'layer_menu_remove'), isFalse);
    expect(enabled(tester, 'layer_menu_opacity'), isFalse);
    expect(enabled(tester, 'layer_menu_color'), isFalse);
    await tester.tap(find.byKey(const Key('layer_menu_remove_others')));
    await tester.pumpAndSettle();
    expect(find.text('Карта остаётся всегда — её можно только сменить'), findsOneWidget);
    expect(h.state.overlays, hasLength(1));
  });

  testWidgets('the top layer can be moved down, the others up; a single layer cannot move', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer, osmLayer]));
    await openMenu(tester, 'osm-standard');
    expect(find.text('Переместить вниз'), findsOneWidget);
    expect(find.text('Переместить вверх'), findsNothing);
    await tester.tap(find.byKey(const Key('layer_menu_move_up')));
    await tester.pumpAndSettle();
    expect(h.state.overlays.map((l) => l.sourceId), ['osm-standard', 'yandex-hybrid']);
    expect(find.text('Переместить вверх'), findsOneWidget, reason: 'no longer on top');
    await tester.tap(find.byKey(const Key('layer_menu_move_up')));
    await tester.pumpAndSettle();
    expect(h.state.overlays.map((l) => l.sourceId), ['yandex-hybrid', 'osm-standard']);
  });

  testWidgets('a single layer cannot move', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    expect(enabled(tester, 'layer_menu_move_up'), isFalse);
  });

  testWidgets('«Сравнить...» picks layers, closes the panel and starts the compare mode', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer, osmLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_compare')));
    await tester.pumpAndSettle();
    expect(find.byType(CompareSelectDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('compare_select_osm-standard')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('compare_select_ok')));
    await tester.pumpAndSettle();
    expect(find.byType(LayersPanel), findsNothing);
    expect(h.container.read(compareRequestProvider), ['osm-standard', 'yandex-hybrid']);
  });

  testWidgets('nothing to compare without layers or for the orthophotos', (tester) async {
    await h.pump(tester);
    await openMenu(tester, 'base');
    expect(enabled(tester, 'layer_menu_compare'), isFalse);
    await tester.tap(find.byKey(const Key('layer_menu_cancel')));
    await tester.pumpAndSettle();
    await openMenu(tester, MapStateNotifier.orthophotosKey);
    expect(enabled(tester, 'layer_menu_compare'), isFalse);
  });

  testWidgets('«Непрозрачность» opens the slider sheet', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_opacity')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerContextMenu), findsNothing);
    expect(find.byType(LayerOpacitySheet), findsOneWidget);
  });

  testWidgets('«Детали» opens the layer details screen', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_details')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerDetailsScreen), findsOneWidget);
    expect(find.text('Яндекс'), findsOneWidget); // группа в шапке
    expect(find.text('Гибрид · Растр · Онлайн'), findsOneWidget);
  });

  testWidgets('«Инверсия цветов» toggles and inverts the layer on the map', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_invert')));
    await tester.pumpAndSettle();
    expect(h.container.read(layerLooksProvider)['yandex-hybrid']!.color.inverted, isTrue);
    expect(h.host.colors[layerId('yandex-hybrid')]!.brightnessMin, 1);
    expect(h.host.colors[layerId('yandex-hybrid')]!.brightnessMax, 0);
    await tester.tap(find.byKey(const Key('layer_menu_invert')));
    await tester.pumpAndSettle();
    expect(h.container.read(layerLooksProvider), isEmpty);
    expect(h.host.colors[layerId('yandex-hybrid')], RasterColor.none);
  });

  testWidgets('force refresh asks, then is ticked for this session', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_force_refresh')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Изменение действует только в текущей сессии'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(h.container.read(layerLooksProvider)['yandex-hybrid']!.forceRefresh, isTrue);
    expect(
      find.descendant(of: find.byKey(const Key('layer_menu_force_refresh')), matching: find.byIcon(Icons.check_box)),
      findsOneWidget,
    );
  });

  testWidgets('«Изменить цвет»: sliders change the map at once, ОТМЕНА puts it back', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_color')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerColorSheet), findsOneWidget);

    final saturation = find.descendant(of: find.byKey(const Key('color_saturation')), matching: find.byType(Slider));
    tester.widget<Slider>(saturation).onChanged!(0);
    await tester.pumpAndSettle();
    expect(h.host.colors[layerId('yandex-hybrid')]!.saturation, -1);

    await tester.tap(find.byKey(const Key('look_cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerColorSheet), findsNothing);
    expect(h.host.colors[layerId('yandex-hybrid')], RasterColor.none);
  });

  testWidgets('«Изменить цвет»: СБРОСИТЬ returns the defaults, ОК keeps the change', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_color')));
    await tester.pumpAndSettle();
    final brightness = find.descendant(of: find.byKey(const Key('color_brightness')), matching: find.byType(Slider));
    tester.widget<Slider>(brightness).onChanged!(50);
    await tester.pumpAndSettle();
    expect(h.host.colors[layerId('yandex-hybrid')]!.brightnessMin, 0.5);
    await tester.tap(find.byKey(const Key('look_reset')));
    await tester.pumpAndSettle();
    expect(h.host.colors[layerId('yandex-hybrid')], RasterColor.none);
    tester.widget<Slider>(brightness).onChanged!(-50);
    await tester.tap(find.byKey(const Key('look_ok')));
    await tester.pumpAndSettle();
    expect(h.container.read(layerLooksProvider)['yandex-hybrid']!.color.brightness, -0.5);
  });

  testWidgets('«Удалить цвет»: switch and channel sliders are kept for the session', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_erase')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerEraseColorSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('erase_enabled')));
    await tester.pumpAndSettle();
    final red = find.descendant(of: find.byKey(const Key('erase_channel_0')), matching: find.byType(Slider));
    tester.widget<Slider>(red).onChanged!(200);
    await tester.pumpAndSettle();
    final erase = h.container.read(layerLooksProvider)['yandex-hybrid']!.erase;
    expect(erase.enabled, isTrue);
    expect(erase.ranges.map((r) => r.center), [200, 255, 255]);
    expect(erase.screenCenterHex, '#C8FFFF');
  });

  testWidgets('«Режим смешивания слоёв»: one mode is picked and the sheet closes', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_blending')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerBlendingSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('blending_multiply')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerBlendingSheet), findsNothing);
    expect(h.container.read(layerLooksProvider)['yandex-hybrid']!.blending, LayerBlending.multiply);
  });

  testWidgets('removing a layer drops its look', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_invert')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layer_menu_remove')));
    await tester.pumpAndSettle();
    expect(h.container.read(layerLooksProvider), isEmpty);
  });
}
