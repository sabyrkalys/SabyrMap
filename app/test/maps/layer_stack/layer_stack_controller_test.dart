import 'package:app/maps/color/erase_color_settings.dart';
import 'package:app/maps/color/layer_color_settings.dart';
import 'package:app/maps/layer_stack/layer_blending.dart';
import 'package:app/maps/layer_stack/layer_entry.dart';
import 'package:app/maps/layer_stack/layer_stack_controller.dart';
import 'package:app/maps/settings/maps_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late MapsSettings settings;
  late LayerStackController c;
  setUp(() async {
    settings = await freshMapsSettings();
    c = LayerStackController(settings);
    await c.load();
  });

  List<String> ids() => [for (final l in c.state.stack) l.id];
  List<int> orders() => [for (final l in c.state.stack) l.order];
  Future<void> addThree() async {
    for (final id in ['base', 'topo', 'hills']) {
      await c.add(LayerEntry(id: id, sourceId: 'mbtiles', order: 99));
    }
  }

  test('add puts the layer on top, renumbers and selects it', () async {
    await addThree();
    expect(ids(), ['base', 'topo', 'hills']);
    expect(orders(), [0, 1, 2]);
    expect(c.state.selectedLayerId, 'hills');
    expect(c.state.count, 3);
    expect(() => c.add(const LayerEntry(id: 'base', sourceId: 'x')), throwsArgumentError);
  });

  test('remove renumbers and drops the selection', () async {
    await addThree();
    await c.remove('hills');
    expect(ids(), ['base', 'topo']);
    expect(orders(), [0, 1]);
    expect(c.state.selected, isNull);
    c.select('base');
    await c.remove('topo');
    expect(c.state.selectedLayerId, 'base');
  });

  test('moveUp and moveDown change the order; edges stay', () async {
    await addThree();
    await c.moveUp('base');
    expect(ids(), ['topo', 'base', 'hills']);
    await c.moveDown('hills');
    expect(ids(), ['topo', 'hills', 'base']);
    await c.moveUp('base');
    await c.moveDown('topo');
    expect(ids(), ['topo', 'hills', 'base']);
    expect(orders(), [0, 1, 2]);
  });

  test('reorder clamps the index', () async {
    await addThree();
    await c.reorder('base', 99);
    expect(ids(), ['topo', 'hills', 'base']);
    await c.reorder('base', -5);
    expect(ids(), ['base', 'topo', 'hills']);
  });

  test('setOpacity (clamped), visible, blending, colour, erase colour', () async {
    await addThree();
    await c.setOpacity('topo', 0.4);
    expect(c.state.stack[1].opacity, 0.4);
    await c.setOpacity('topo', 3);
    expect(c.state.stack[1].opacity, 1);
    await c.setVisible('base', false);
    expect(c.state.visibleLayers.map((l) => l.id), ['topo', 'hills']);
    await c.setBlending('hills', LayerBlending.multiply);
    await c.setColor('hills', const LayerColorSettings(contrast: 1.5));
    await c.setEraseColor('hills', EraseColorSettings.fromColor(0xFFFFFFFF));
    final hills = c.state.stack.last;
    expect(hills.blending, LayerBlending.multiply);
    expect(hills.color.contrast, 1.5);
    expect(hills.eraseColor!.enabled, isTrue);
  });

  test('clear empties the stack', () async {
    await addThree();
    await c.clear();
    expect(c.state.count, 0);
    expect(c.state.selected, isNull);
  });

  test('persist + load restore the whole stack', () async {
    await addThree();
    await c.setOpacity('topo', 0.25);
    await c.setBlending('base', LayerBlending.screen);
    await c.persist();
    final again = LayerStackController(settings);
    await again.load();
    expect(again.state.stack, c.state.stack);
  });

  test('a broken record loads as an empty stack', () async {
    await settings.setLayerStackJson('{nope');
    await c.load();
    expect(c.state.count, 0);
  });
}
