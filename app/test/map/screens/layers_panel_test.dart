import 'package:app/map/screens/available_maps_screen.dart';
import 'package:app/map/screens/layers_panel.dart';
import 'package:app/map/screens/on_screen/favorite_set_save_dialog.dart';
import 'package:app/map/screens/on_screen/layer_context_menu.dart';
import 'package:app/map/screens/on_screen/layer_opacity_sheet.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'on_screen/harness.dart';

void main() {
  final h = LayersHarness();

  List<String> rowTitles(WidgetTester tester) => [
        for (final finder in [find.text('OSM Standard Raster'), find.text('Яндекс Гибрид'), find.text('Базовая карта')])
          if (finder.evaluate().isNotEmpty) '${tester.getTopLeft(finder.first).dy}',
      ];

  testWidgets('layers top → bottom, the base map last without eye and opacity buttons', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer, osmLayer]));
    expect(find.byType(LayersPanel), findsOneWidget);
    expect(find.text('Карты на экране'), findsOneWidget);
    final osmY = tester.getTopLeft(find.text('OSM Standard Raster')).dy;
    final hybridY = tester.getTopLeft(find.text('Яндекс Гибрид')).dy;
    final baseY = tester.getTopLeft(find.text('Базовая карта')).dy;
    expect(osmY < hybridY && hybridY < baseY, isTrue, reason: rowTitles(tester).join(' '));
    expect(find.text('OpenFreeMap Liberty'), findsOneWidget);
    final baseRow = find.byKey(const Key('layer_base_row'));
    expect(find.descendant(of: baseRow, matching: find.byIcon(Icons.visibility)), findsNothing);
    expect(find.descendant(of: baseRow, matching: find.byIcon(Icons.layers_outlined)), findsNothing);
    expect(find.descendant(of: baseRow, matching: find.byIcon(Icons.more_vert)), findsOneWidget);
  });

  testWidgets('row: «N % непрозрачн.», the eye hides the layer and changes its icon', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    expect(find.text('75 % непрозрачн.'), findsOneWidget);
    final eye = find.byKey(const Key('layer_visible_yandex-hybrid'));
    expect(find.descendant(of: eye, matching: find.byIcon(Icons.visibility)), findsOneWidget);
    await tester.tap(eye);
    await tester.pumpAndSettle();
    expect(h.state.overlays.single.visible, isFalse);
    expect(h.host.opacities[LayerManager.layerIdOf('yandex-hybrid')], 0);
    expect(find.descendant(of: eye, matching: find.byIcon(Icons.visibility_off)), findsOneWidget);
  });

  testWidgets('the layers icon and a tap on the row open the opacity sheet', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await tester.tap(find.byKey(const Key('layer_opacity_yandex-hybrid')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerOpacitySheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('opacity_done')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Яндекс Гибрид'));
    await tester.pumpAndSettle();
    expect(find.byType(LayerOpacitySheet), findsOneWidget);
  });

  testWidgets('three dots open the layer menu, also for the base map', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await tester.tap(find.byKey(const Key('layer_menu_yandex-hybrid')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerContextMenu), findsOneWidget);
    await tester.tap(find.byKey(const Key('layer_menu_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layer_menu_base')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerContextMenu), findsOneWidget);
    expect(find.text('OpenFreeMap Liberty'), findsNWidgets(2)); // строка и заголовок меню
  });

  testWidgets('header: the cross closes the panel', (tester) async {
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('layers_header_close')));
    await tester.pumpAndSettle();
    expect(find.byType(LayersPanel), findsNothing);
  });

  testWidgets('header: the map icon closes the panel and opens the available maps', (tester) async {
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('layers_header_maps')));
    await tester.pumpAndSettle();
    expect(find.byType(LayersPanel), findsNothing);
    expect(find.byType(AvailableMapsScreen), findsOneWidget);
  });

  testWidgets('header: the bookmark saves the screen as a favourite set', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await tester.tap(find.byKey(const Key('layers_header_save')));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteSetNameDialog), findsOneWidget);
    await tester.enterText(find.byKey(const Key('favorite_set_name')), ' Гибрид ');
    await tester.tap(find.byKey(const Key('favorite_set_ok')));
    await tester.pumpAndSettle();
    final preset = h.state.presets.single;
    expect(preset.name, 'Гибрид');
    expect(preset.baseSourceId, 'ofm-liberty');
    expect(preset.overlays.single.sourceId, 'yandex-hybrid');
    expect(find.text('Набор сохранён'), findsOneWidget);
  });

  testWidgets('reordering the list reorders the layers (top of the list = top of the map)', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer, osmLayer]));
    final list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    // Сверху вниз: OSM (z20), затем Гибрид (z10). Гибрид — наверх.
    list.onReorderItem!(1, 0);
    await tester.pumpAndSettle();
    expect(h.state.overlays.map((l) => l.sourceId), ['osm-standard', 'yandex-hybrid']);
  });

  testWidgets('«Добавить слой» opens the catalog in overlay-picking mode', (tester) async {
    await h.pump(tester);
    expect(find.text('Добавить слой (0/3)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('layers_add')));
    await tester.pumpAndSettle();
    expect(find.byType(AvailableMapsScreen), findsOneWidget);
    expect(find.text('Добавить слой'), findsOneWidget);
  });

  testWidgets('over a Google base, adding is refused with the reason', (tester) async {
    await h.pump(tester, saved: stateWith(const [], base: 'google-satellite'));
    await tester.tap(find.byKey(const Key('layers_add')));
    await tester.pumpAndSettle();
    expect(find.byType(AvailableMapsScreen), findsNothing);
    expect(find.text(LayerManager.isolatedMessage), findsOneWidget);
  });

  testWidgets('a tap on the base row opens the available maps to change it', (tester) async {
    await h.pump(tester);
    await tester.tap(find.text('Базовая карта'));
    await tester.pumpAndSettle();
    expect(find.byType(AvailableMapsScreen), findsOneWidget);
  });

}
