import 'package:app/map/models/layer_look.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/map/screens/on_screen/favorite_sets_section.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:app/maps/color/layer_color_settings.dart';
import 'package:app/maps/layer_stack/layer_blending.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  final h = LayersHarness();
  var applied = 0;

  const preset = MapPreset(
    id: 'p1',
    name: 'Спутник + гибрид',
    baseSourceId: 'yandex-sat',
    overlays: [hybridLayer],
    looks: {'yandex-hybrid': LayerLook(color: LayerColorSettings(inverted: true), blending: LayerBlending.multiply)},
  );

  Future<void> pump(WidgetTester tester, {List<MapPreset> presets = const []}) async {
    applied = 0;
    await h.pump(
      tester,
      saved: stateWith(const [], presets: presets),
      child: SingleChildScrollView(child: FavoriteSetsSection(onApplied: () => applied++)),
    );
  }

  testWidgets('empty: the hint is shown', (tester) async {
    await pump(tester);
    expect(find.text('ИЗБРАННЫЕ КАРТЫ И НАБОРЫ КАРТ'), findsOneWidget);
    expect(find.text('Избранные карты и наборы карт не созданы'), findsOneWidget);
  });

  testWidgets('not empty: one tile per set; a tap applies it with its looks and closes the menu', (tester) async {
    await pump(tester, presets: const [preset, MapPreset(id: 'p2', name: 'Пусто', baseSourceId: 'ofm-liberty', overlays: [])]);
    expect(find.text('Избранные карты и наборы карт не созданы'), findsNothing);
    expect(find.text('Спутник + гибрид'), findsOneWidget);
    expect(find.text('Пусто'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_outline), findsNWidgets(2));

    await tester.tap(find.text('Спутник + гибрид'));
    await tester.pumpAndSettle();
    expect(applied, 1);
    expect(h.state.baseSourceId, 'yandex-sat');
    expect(h.state.overlays.single.sourceId, 'yandex-hybrid');
    expect(h.container.read(layerLooksProvider)['yandex-hybrid']!.blending, LayerBlending.multiply);
    expect(h.host.colors[LayerManager.layerIdOf('yandex-hybrid')]!.brightnessMin, 1);
  });

  testWidgets('the save dialog with a name creates a set holding the looks', (tester) async {
    await pump(tester);
    await h.container.read(mapLayersProvider.notifier).addOverlay(osm);
    await h.container
        .read(mapLayersProvider.notifier)
        .setLook('osm-standard', const LayerLook(color: LayerColorSettings(saturation: 0), forceRefresh: true));
    await tester.tap(find.byKey(const Key('favorite_sets_add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite_set_ok')));
    await tester.pumpAndSettle();
    expect(h.state.presets, isEmpty, reason: 'an empty name is not accepted');
    await tester.enterText(find.byKey(const Key('favorite_set_name')), 'Серый OSM');
    await tester.tap(find.byKey(const Key('favorite_set_ok')));
    await tester.pumpAndSettle();
    final saved = h.state.presets.single;
    expect(saved.name, 'Серый OSM');
    expect(saved.overlays.single.sourceId, 'osm-standard');
    expect(saved.looks['osm-standard'], const LayerLook(color: LayerColorSettings(saturation: 0)));
    expect(find.text('Серый OSM'), findsOneWidget);
    expect(MapPreset.fromJson(saved.toJson()), saved);
  });

  testWidgets('menu: rename', (tester) async {
    await pump(tester, presets: const [preset]);
    await tester.tap(find.byKey(const Key('favorite_set_menu_p1')));
    await tester.pumpAndSettle();
    expect(find.text('Применить'), findsOneWidget);
    await tester.tap(find.byKey(const Key('favorite_menu_rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('favorite_set_name')), 'Ночь');
    await tester.tap(find.byKey(const Key('favorite_set_ok')));
    await tester.pumpAndSettle();
    expect(h.state.presets.single.name, 'Ночь');
    expect(h.state.presets.single.looks, preset.looks);
  });

  testWidgets('menu: delete asks first; a long press opens the menu too', (tester) async {
    await pump(tester, presets: const [preset]);
    await tester.longPress(find.text('Спутник + гибрид'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite_menu_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(h.state.presets, hasLength(1));

    await tester.tap(find.byKey(const Key('favorite_set_menu_p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite_menu_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(h.state.presets, isEmpty);
    expect(find.text('Избранные карты и наборы карт не созданы'), findsOneWidget);
  });
}
