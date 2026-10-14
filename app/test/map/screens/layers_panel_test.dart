import 'package:app/map/screens/available_maps_screen.dart';
import 'package:app/map/screens/layers_panel.dart';
import 'package:app/map/screens/on_screen/favorite_set_save_dialog.dart';
import 'package:app/map/screens/on_screen/layer_context_menu.dart';
import 'package:app/map/screens/on_screen/layer_opacity_sheet.dart';
import 'package:app/map/services/layer_manager.dart';
import 'dart:io';

import 'package:app/map/screens/on_screen/on_screen_layer_row.dart';
import 'package:app/map/services/map_previews.dart';
import 'package:app/map/models/layer_look.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:app/maps/color/erase_color_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'on_screen/harness.dart';

void main() {
  final h = LayersHarness();

  List<String> rowTitles(WidgetTester tester) => [
        for (final finder in [find.text('OSM Standard Raster'), find.text('Яндекс Гибрид'), find.text('Базовая карта')])
          if (finder.evaluate().isNotEmpty) '${tester.getTopLeft(finder.first).dy}',
      ];

  testWidgets('layers top → bottom, then the map (eye, no opacity button), then the base map', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer, osmLayer]));
    expect(find.byType(LayersPanel), findsOneWidget);
    expect(find.text('Карты на экране'), findsOneWidget);
    final osmY = tester.getTopLeft(find.text('OSM Standard Raster')).dy;
    final hybridY = tester.getTopLeft(find.text('Яндекс Гибрид')).dy;
    final baseY = tester.getTopLeft(find.text('Базовая карта')).dy;
    expect(osmY < hybridY && hybridY < baseY, isTrue, reason: rowTitles(tester).join(' '));
    expect(find.text('OpenFreeMap Liberty'), findsOneWidget);
    final baseRow = find.byKey(const Key('layer_base_row'));
    expect(find.descendant(of: baseRow, matching: find.byIcon(Icons.visibility)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('layer_world_row')), matching: find.byIcon(Icons.visibility)),
        findsNothing);
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

  testWidgets('the layers icon and a tap on the row hide the panel behind the opacity sheet; ✓ brings it back',
      (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await tester.tap(find.byKey(const Key('layer_opacity_yandex-hybrid')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerOpacitySheet), findsOneWidget);
    expect(find.byType(LayersPanel), findsNothing);
    await tester.tap(find.byKey(const Key('opacity_done')));
    await tester.pumpAndSettle();
    expect(find.byType(LayerOpacitySheet), findsNothing);
    expect(find.byType(LayersPanel), findsOneWidget);

    await tester.tap(find.text('Яндекс Гибрид'));
    await tester.pumpAndSettle();
    expect(find.byType(LayerOpacitySheet), findsOneWidget);
    expect(find.byType(LayersPanel), findsNothing);
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

  testWidgets('a long press on a layer or on the base map opens the layer menu', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await tester.longPress(find.text('Яндекс Гибрид'));
    await tester.pumpAndSettle();
    expect(find.byType(LayerContextMenu), findsOneWidget);
    expect(find.byType(LayersPanel), findsOneWidget, reason: 'the menu opens over the panel');
    await tester.tap(find.byKey(const Key('layer_menu_cancel')));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Базовая карта'));
    await tester.pumpAndSettle();
    expect(find.byType(LayerContextMenu), findsOneWidget);
    expect(find.byType(AvailableMapsScreen), findsNothing);
  });

  testWidgets('dragging a layer by its ≡ handle reorders the map (top of the list = top of the map)', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer, osmLayer]));
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    // Сверху вниз: OSM, затем Гибрид. Тянем Гибрид за ручку наверх.
    final handle = find.byKey(const Key('layer_drag_yandex-hybrid'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, -200), timeStamp: const Duration(milliseconds: 100));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -50));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.state.overlays.map((l) => l.sourceId), ['osm-standard', 'yandex-hybrid']);
  });

  testWidgets('moving a layer down the list puts it right below its new neighbour', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer, osmLayer]));
    tester.widget<ReorderableListView>(find.byType(ReorderableListView)).onReorderItem!(0, 1);
    await tester.pumpAndSettle();
    expect(h.state.overlays.map((l) => l.sourceId), ['osm-standard', 'yandex-hybrid']);
  });

  testWidgets('orthophotos: one row above the layers; its eye is the map switch', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    const key = MapStateNotifier.orthophotosKey;
    expect(find.text('Ортофотопланы'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Ортофотопланы')).dy < tester.getTopLeft(find.text('Яндекс Гибрид')).dy, isTrue);
    expect(find.byKey(const Key('layer_drag_$key')), findsNothing);
    final eye = find.byKey(const Key('layer_visible_$key'));
    expect(find.descendant(of: eye, matching: find.byIcon(Icons.visibility_off)), findsOneWidget);

    await tester.tap(eye);
    await tester.pumpAndSettle();
    expect(h.state.orthophotosOn, isTrue);
    expect(find.descendant(of: eye, matching: find.byIcon(Icons.visibility)), findsOneWidget);
    await tester.tap(eye);
    await tester.pumpAndSettle();
    expect(h.state.orthophotosOn, isFalse);
  });

  testWidgets('orthophotos: the slider sets the opacity of all of them', (tester) async {
    await h.pump(tester);
    await tester.tap(find.text('Ортофотопланы'));
    await tester.pumpAndSettle();
    expect(find.text('Непрозрачность · Ортофотопланы'), findsOneWidget);
    tester.widget<Slider>(find.byKey(const Key('opacity_slider'))).onChangeEnd!(60);
    await tester.pumpAndSettle();
    expect(h.state.orthophotoOpacity, 0.6);
  });

  testWidgets('orthophotos: the menu changes only their look', (tester) async {
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('layer_menu_${MapStateNotifier.orthophotosKey}')));
    await tester.pumpAndSettle();
    bool enabled(String key) =>
        tester.widget<InkWell>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(InkWell)).first).onTap != null;
    for (final key in ['layer_menu_remove', 'layer_menu_remove_others', 'layer_menu_move_up', 'layer_menu_force_refresh']) {
      expect(enabled(key), isFalse, reason: key);
    }
    for (final key in ['layer_menu_details', 'layer_menu_opacity', 'layer_menu_color', 'layer_menu_invert']) {
      expect(enabled(key), isTrue, reason: key);
    }
    await tester.tap(find.byKey(const Key('layer_menu_invert')));
    await tester.pumpAndSettle();
    expect(h.container.read(layerLooksProvider)[MapStateNotifier.orthophotosKey]!.color.inverted, isTrue);
  });

  testWidgets('the built-in base map is the last row; its opacity is set and kept', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    final mapY = tester.getTopLeft(find.byKey(const Key('layer_base_row'))).dy;
    final worldY = tester.getTopLeft(find.byKey(const Key('layer_world_row'))).dy;
    expect(mapY < worldY, isTrue);
    expect(find.descendant(of: find.byKey(const Key('layer_base_row')), matching: find.text('Карта')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('layer_world_row')), matching: find.text('100 % непрозрачн.')),
        findsOneWidget);

    await tester.tap(find.text('Базовая карта'));
    await tester.pumpAndSettle();
    expect(find.text('Непрозрачность · Базовая карта'), findsOneWidget);
    tester.widget<Slider>(find.byKey(const Key('opacity_slider'))).onChangeEnd!(30);
    await tester.pumpAndSettle();
    expect(h.state.worldOpacity, 0.3);
    expect(h.store.saved!.worldOpacity, 0.3);
  });

  testWidgets('the map row has an eye that hides the chosen map (remembered); the base map has a picture', (tester) async {
    await h.pump(tester);
    final eye = find.byKey(const Key('layer_base_visible'));
    expect(find.descendant(of: eye, matching: find.byIcon(Icons.visibility)), findsOneWidget);
    await tester.tap(eye);
    await tester.pumpAndSettle();
    expect(h.state.mapVisible, isFalse);
    expect(h.store.saved!.mapVisible, isFalse);
    expect(find.descendant(of: eye, matching: find.byIcon(Icons.visibility_off)), findsOneWidget);
    await tester.tap(eye);
    await tester.pumpAndSettle();
    expect(h.state.mapVisible, isTrue);

    final ink = tester.widget<Ink>(
      find.descendant(of: find.byKey(const Key('layer_world_row')), matching: find.byType(Ink)).first,
    );
    expect(((ink.decoration! as BoxDecoration).image!.image as AssetImage).assetName, 'assets/base/world_preview.jpg');
  });

  testWidgets('the base map menu offers only details and opacity', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer]));
    await tester.tap(find.byKey(const Key('layer_menu_world')));
    await tester.pumpAndSettle();
    bool enabled(String key) =>
        tester.widget<InkWell>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(InkWell)).first).onTap != null;
    expect(enabled('layer_menu_details'), isTrue);
    expect(enabled('layer_menu_opacity'), isTrue);
    for (final key in [
      'layer_menu_compare',
      'layer_menu_remove',
      'layer_menu_remove_others',
      'layer_menu_move_up',
      'layer_menu_color',
      'layer_menu_invert',
    ]) {
      expect(enabled(key), isFalse, reason: key);
    }
  });

  testWidgets('a layer with «Удалить цвет» on shows it in red under its opacity', (tester) async {
    await h.pump(tester, saved: stateWith(const [hybridLayer, osmLayer]));
    expect(find.byKey(const Key('layer_status_erase')), findsNothing);
    await h.container
        .read(mapLayersProvider.notifier)
        .setLook('yandex-hybrid', LayerLook(erase: EraseColorSettings.fromColor(0xFF3A152D)));
    await tester.pumpAndSettle();
    final status = find.byKey(const Key('layer_status_erase'));
    expect(status, findsOneWidget);
    expect(tester.widget<Text>(status).data, 'Удалить цвет');
    expect(find.descendant(of: find.ancestor(of: find.text('Яндекс Гибрид'), matching: find.byType(Column)).first, matching: status),
        findsOneWidget);
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

  testWidgets('a tap on the map row opens the available maps to change it', (tester) async {
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('layer_base_row')));
    await tester.pumpAndSettle();
    expect(find.byType(AvailableMapsScreen), findsOneWidget);
  });


  testWidgets('rows have the map picture as a pale background; without one they stay white', (tester) async {
    await h.pump(
      tester,
      saved: stateWith(const [hybridLayer, osmLayer]),
      overrides: [
        mapPreviewProvider.overrideWith((ref, source) async => source.id == 'osm-standard' ? null : File('/no/${source.id}.jpg')),
      ],
    );
    DecorationImage? backgroundOf(Finder row) {
      final ink = tester.widget<Ink>(find.descendant(of: row, matching: find.byType(Ink)).first);
      return (ink.decoration as BoxDecoration?)?.image;
    }

    final rows = find.byType(LayerRowBackground);
    final hybrid = find.ancestor(of: find.text('Яндекс Гибрид'), matching: rows);
    final osmRow = find.ancestor(of: find.text('OSM Standard Raster'), matching: rows);
    final base = find.byKey(const Key('layer_base_row'));
    expect((backgroundOf(hybrid)!.image as FileImage).file.path, '/no/yandex-hybrid.jpg');
    expect(backgroundOf(hybrid)!.opacity, LayerRowBackground.previewOpacity);
    expect((backgroundOf(base)!.image as FileImage).file.path, '/no/ofm-liberty.jpg');
    expect(backgroundOf(osmRow), isNull);
  });
}
