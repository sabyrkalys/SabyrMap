import 'dart:async';

import 'package:app/menu/menu_toggles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements MenuTogglesStore {
  _MemoryStore([Map<String, bool>? initial]) : saved = {...?initial};
  Map<String, bool> saved;
  @override
  Future<Map<String, bool>> load() async => {...saved};
  @override
  Future<void> save(Map<String, bool> values) async => saved = {...values};
}

class _SlowStore implements MenuTogglesStore {
  final pendingLoad = Completer<Map<String, bool>>();
  Map<String, bool> saved = {};
  @override
  Future<Map<String, bool>> load() => pendingLoad.future;
  @override
  Future<void> save(Map<String, bool> values) async => saved = {...values};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerWith(MenuTogglesStore store) {
    final container = ProviderContainer(overrides: [menuTogglesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    return container;
  }

  test('starts with the mockup defaults', () {
    final state = containerWith(_MemoryStore()).read(menuTogglesProvider);
    expect(state[MenuToggle.waypointsNames], isTrue);
    expect(state[MenuToggle.positioningRotateByMovement], isFalse);
    expect(state[MenuToggle.orientationRotateByCompass], isTrue);
    expect(state[MenuToggle.orientationShowCompass], isFalse);
    expect(state.length, MenuToggle.values.length);
  });

  test('saved values override defaults once loaded; unknown keys are ignored', () async {
    final container = containerWith(_MemoryStore({'waypointsNames': false, 'noSuchToggle': true}));
    container.read(menuTogglesProvider);
    await Future<void>.delayed(Duration.zero);
    final state = container.read(menuTogglesProvider);
    expect(state[MenuToggle.waypointsNames], isFalse);
    expect(state[MenuToggle.waypointsTargetLine], isTrue);
  });

  test('set updates state and saves every value by name', () async {
    final store = _MemoryStore();
    final container = containerWith(store);
    container.read(menuTogglesProvider);
    await Future<void>.delayed(Duration.zero);

    container.read(menuTogglesProvider.notifier).set(MenuToggle.mapsScaleBar, true);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(menuTogglesProvider)[MenuToggle.mapsScaleBar], isTrue);
    expect(store.saved['mapsScaleBar'], isTrue);
    expect(store.saved.length, MenuToggle.values.length);
  });

  test('a change made before the saved values load does not overwrite the other saved values', () async {
    final store = _SlowStore();
    final container = containerWith(store);
    container.read(menuTogglesProvider);

    container.read(menuTogglesProvider.notifier).set(MenuToggle.mapsScaleBar, true);
    store.pendingLoad.complete({'waypointsNames': false});
    await Future<void>.delayed(Duration.zero);

    expect(store.saved['mapsScaleBar'], isTrue);
    expect(store.saved['waypointsNames'], isFalse);
  });

  group('SecureMenuTogglesStore', () {
    test('round-trips values', () async {
      FlutterSecureStorage.setMockInitialValues({});
      await SecureMenuTogglesStore().save({'a': true, 'b': false});
      expect(await SecureMenuTogglesStore().load(), {'a': true, 'b': false});
    });

    test('corrupt data loads as empty', () async {
      FlutterSecureStorage.setMockInitialValues({'menu_toggles': 'not json'});
      expect(await SecureMenuTogglesStore().load(), isEmpty);
    });

    test('non-bool entries are skipped', () async {
      FlutterSecureStorage.setMockInitialValues({'menu_toggles': '{"a": true, "b": 3}'});
      expect(await SecureMenuTogglesStore().load(), {'a': true});
    });
  });
}
