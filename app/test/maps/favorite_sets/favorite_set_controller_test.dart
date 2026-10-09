import 'package:app/maps/color/layer_color_settings.dart';
import 'package:app/maps/favorite_sets/favorite_set_controller.dart';
import 'package:app/maps/favorite_sets/favorite_set_store.dart';
import 'package:app/maps/layer_stack/layer_blending.dart';
import 'package:app/maps/layer_stack/layer_entry.dart';
import 'package:app/maps/layer_stack/layer_stack_controller.dart';
import 'package:app/maps/settings/maps_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late LayerStackController layers;
  late FavoriteSetController c;
  setUp(() async {
    final settings = await freshSettings();
    layers = LayerStackController(MapsSettings(settings));
    c = FavoriteSetController(FavoriteSetStore(settings), layers, clock: () => DateTime.fromMillisecondsSinceEpoch(1000));
    await c.loadAll();
    await layers.add(const LayerEntry(id: 'base', sourceId: 'mbtiles'));
    await layers.add(
      const LayerEntry(
        id: 'hills',
        sourceId: 'aqx',
        opacity: 0.4,
        color: LayerColorSettings(brightness: 0.2),
        blending: LayerBlending.multiply,
      ),
    );
  });

  test('saveCurrentAs takes the current stack', () async {
    final set = await c.saveCurrentAs('  Hiking ');
    expect(set.name, 'Hiking');
    expect(set.layers, layers.state.stack);
    expect(set.createdAt, 1000);
    expect(c.sets.single.id, set.id);
    expect(() => c.saveCurrentAs(' '), throwsArgumentError);
  });

  test('apply restores opacity, colour and blending', () async {
    final set = await c.saveCurrentAs('Hiking');
    await layers.clear();
    await layers.add(const LayerEntry(id: 'other', sourceId: 'pgd'));
    await c.apply(set.id);
    expect(layers.state.stack.map((l) => l.id), ['base', 'hills']);
    final hills = layers.state.stack.last;
    expect(hills.opacity, 0.4);
    expect(hills.color.brightness, 0.2);
    expect(hills.blending, LayerBlending.multiply);
    expect(() => c.apply('nope'), throwsStateError);
  });

  test('rename changes the name; remove deletes', () async {
    final set = await c.saveCurrentAs('Hiking');
    await c.rename(set.id, 'Trekking');
    expect(c.sets.single.name, 'Trekking');
    expect(c.sets.single.createdAt, 1000);
    await c.remove(set.id);
    expect(c.sets, isEmpty);
  });
}
