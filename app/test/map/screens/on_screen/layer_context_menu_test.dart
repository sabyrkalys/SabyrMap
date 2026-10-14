import 'package:app/map/screens/compare/compare_mode_screen.dart';
import 'package:app/map/screens/compare/compare_select_dialog.dart';
import 'package:app/map/screens/layer_details/layer_details_screen.dart';
import 'package:app/map/screens/layer_look/erase_color_screen.dart';
import 'package:app/map/screens/layer_look/layer_color_screen.dart';
import 'package:app/map/screens/layers_panel.dart';
import 'package:app/map/screens/on_screen/layer_blending_sheet.dart';
import 'package:app/map/screens/on_screen/layer_context_menu.dart';
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

  testWidgets('for the map «Убрать остальные» removes nothing and says why', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'base');
    expect(enabled(tester, 'layer_menu_remove'), isTrue);
    expect(enabled(tester, 'layer_menu_opacity'), isFalse);
    expect(enabled(tester, 'layer_menu_color'), isFalse);
    await tester.tap(find.byKey(const Key('layer_menu_remove_others')));
    await tester.pumpAndSettle();
    expect(find.text('Карта остаётся всегда — её можно только сменить'), findsOneWidget);
    expect(h.state.overlays, hasLength(1));
  });

  testWidgets('«Убрать» on the map removes its row; the base map and layers stay', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'base');
    await tester.tap(find.byKey(const Key('layer_menu_remove')));
    await tester.pumpAndSettle();
    expect(h.state.baseSourceId, LayerManager.noMapId);
    expect(h.state.overlays.single.sourceId, 'yandex-hybrid');
    expect(h.store.saved!.baseSourceId, LayerManager.noMapId);
    expect(find.byKey(const Key('layer_base_row')), findsNothing);
    expect(find.text('Нет карты'), findsNothing);
    expect(find.byKey(const Key('layer_world_row')), findsOneWidget);
    expect(find.text('Яндекс Гибрид'), findsOneWidget);
  });

  testWidgets('without a map: remembered on the next start; a layer has nothing to compare with', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer], base: LayerManager.noMapId));
    expect(h.state.baseSourceId, LayerManager.noMapId);
    expect(h.host.style, contains('"background"'));
    expect(find.byKey(const Key('layer_base_row')), findsNothing);
    await openMenu(tester, 'yandex-hybrid');
    expect(enabled(tester, 'layer_menu_compare'), isFalse);
  });

  testWidgets('picking a map in «Доступные карты» brings its row back', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer], base: LayerManager.noMapId));
    await h.container.read(mapLayersProvider.notifier).setBase(ySat);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layer_base_row')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('layer_base_row')), matching: find.text('Яндекс Спутник')),
        findsOneWidget);
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

  testWidgets('«Изменить цвет» and «Удалить цвет» open their screens and hide the panel until ✓', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_color')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerColorScreen), findsOneWidget);
    expect(find.byType(LayersPanel), findsNothing);
    await tester.tap(find.byKey(const Key('look_done')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerColorScreen), findsNothing);
    expect(find.byType(LayersPanel), findsOneWidget);

    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_erase')));
    await tester.pumpAndSettle();
    expect(find.byType(EraseColorScreen), findsOneWidget);
    expect(find.byType(LayersPanel), findsNothing);
  });

  testWidgets('«Режим смешивания слоёв»: one mode is picked, the sheet closes, the mode is told', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await openMenu(tester, 'yandex-hybrid');
    await tester.tap(find.byKey(const Key('layer_menu_blending')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerBlendingSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('blending_multiply')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerBlendingSheet), findsNothing);
    expect(h.container.read(layerLooksProvider)['yandex-hybrid']!.blending, LayerBlending.multiply);
    expect(find.text('Режим: Умножение'), findsOneWidget);
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
