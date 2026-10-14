import 'package:app/map/screens/compare/compare_mode_screen.dart';
import 'package:app/map/screens/on_screen/favorite_set_save_dialog.dart';
import 'package:app/map/screens/on_screen/layer_context_menu.dart';
import 'package:app/map/models/map_models.dart';
import 'package:app/map/services/layer_manager.dart';
import 'package:app/map/state/map_layers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../on_screen/harness.dart';

void main() {
  final h = LayersHarness();
  const hiddenOsm = ActiveLayerFixtures.hiddenOsm;

  Future<void> start(WidgetTester tester, List<String> ids) async {
    await h.pump(
      tester,
      saved: stateWith(const [hybridLayer, hiddenOsm]),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Consumer(
              builder: (context, ref, _) => switch (ref.watch(compareRequestProvider)) {
                final ids? => CompareModeScreen(key: ValueKey(ids), layerIds: ids),
                null => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      ),
    );
    h.container.read(compareRequestProvider.notifier).start(ids);
    await tester.pumpAndSettle();
  }

  double? opacity(String id) => h.host.opacities[LayerManager.layerIdOf(id)];

  testWidgets('shows only the first layer, named in the panel', (tester) async {
    await start(tester, ['osm-standard', 'yandex-hybrid']);
    expect(find.text('Сравнить...'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('compare_current'))).data, 'OSM Standard Raster');
    expect(opacity('osm-standard'), 0.7, reason: 'hidden before, shown for the comparison');
    expect(opacity('yandex-hybrid'), 0);
  });

  testWidgets('the slider switches layers; the base map hides all of them', (tester) async {
    await start(tester, ['yandex-hybrid', LayerContextMenu.baseId]);
    expect(opacity('yandex-hybrid'), 0.75);
    expect(opacity('osm-standard'), 0, reason: 'not compared, still hidden');
    tester.widget<Slider>(find.byKey(const Key('compare_slider'))).onChanged!(1);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('compare_current'))).data, 'OpenFreeMap Liberty (карта)');
    expect(opacity('yandex-hybrid'), 0);
    expect(h.state.overlays.map((l) => l.visible), [true, false], reason: 'stored visibility is not touched');
  });

  testWidgets('✕ closes and puts the visibility back', (tester) async {
    await start(tester, ['osm-standard', 'yandex-hybrid']);
    await tester.tap(find.byKey(const Key('compare_close')));
    await tester.pumpAndSettle();
    expect(find.byType(CompareModeScreen), findsNothing);
    expect(h.container.read(compareRequestProvider), isNull);
    expect(opacity('osm-standard'), 0);
    expect(opacity('yandex-hybrid'), 0.75);
  });

  testWidgets('system back closes it too', (tester) async {
    await start(tester, ['osm-standard', 'yandex-hybrid']);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CompareModeScreen), findsNothing);
    expect(opacity('yandex-hybrid'), 0.75);
  });

  testWidgets('the bookmark opens the favourite set dialog', (tester) async {
    await start(tester, ['osm-standard', 'yandex-hybrid']);
    await tester.tap(find.byKey(const Key('compare_save')));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteSetNameDialog), findsOneWidget);
  });

  testWidgets('the base map hides the chosen map too; leaving shows it again', (tester) async {
    await start(tester, ['yandex-hybrid', MapStateNotifier.worldKey]);
    // У тестовой карты появляются свои слои.
    h.host.styleLayers = ['background', 'map-fill'];
    await h.container.read(mapLayersProvider.notifier).setBase(liberty);
    await tester.pumpAndSettle();
    expect(h.host.hidden, isEmpty);
    tester.widget<Slider>(find.byKey(const Key('compare_slider'))).onChanged!(1);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('compare_current'))).data, 'Базовая карта');
    expect(opacity('yandex-hybrid'), 0);
    expect(h.host.hidden, isNotEmpty, reason: 'the map style layers are hidden');
    expect(h.state.mapVisible, isTrue, reason: 'not stored');
    await tester.tap(find.byKey(const Key('compare_close')));
    await tester.pumpAndSettle();
    expect(h.host.hidden, isEmpty);
  });
}

abstract final class ActiveLayerFixtures {
  static const hiddenOsm = ActiveLayer(sourceId: 'osm-standard', type: MapLayerType.overlay, opacity: 0.7, visible: false, zIndex: 20);
}
