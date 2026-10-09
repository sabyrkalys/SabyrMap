import 'package:app/maps/favorite_sets/favorite_set.dart';
import 'package:app/maps/favorite_sets/favorite_set_store.dart';
import 'package:app/maps/layer_stack/layer_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late FavoriteSetStore store;
  setUp(() async => store = FavoriteSetStore(await freshSettings()));

  const a = FavoriteSet(
    id: 'a',
    name: 'Hiking',
    layers: [LayerEntry(id: 'l1', sourceId: 'mbtiles', opacity: 0.5)],
    createdAt: 1,
    updatedAt: 2,
  );
  const b = FavoriteSet(id: 'b', name: 'Night', layers: [], createdAt: 3, updatedAt: 3);

  test('an empty store gives an empty list', () async {
    expect(await store.loadAll(), isEmpty);
  });

  test('save and load round-trip; same id replaces', () async {
    await store.save(a);
    await store.save(b);
    expect(await store.loadAll(), [a, b]);
    await store.save(a.copyWith(name: 'Hike'));
    expect((await store.loadAll()).map((s) => s.name), ['Hike', 'Night']);
  });

  test('byId and remove', () async {
    await store.save(a);
    await store.save(b);
    expect(await store.byId('b'), b);
    expect(await store.byId('zzz'), isNull);
    await store.remove('a');
    expect(await store.loadAll(), [b]);
  });
}
