import 'package:app/maps/layer_stack/layer_stack_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'favorite_set.dart';
import 'favorite_set_store.dart';

/// Избранные наборы слоёв: сохранить текущий стек, применить, переименовать.
class FavoriteSetController extends ChangeNotifier {
  FavoriteSetController(this._store, this._layers, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final FavoriteSetStore _store;
  final LayerStackController _layers;
  final DateTime Function() _clock;
  List<FavoriteSet> _sets = const [];

  List<FavoriteSet> get sets => _sets;

  Future<void> loadAll() async {
    _sets = List.unmodifiable(await _store.loadAll());
    notifyListeners();
  }

  /// Сохраняет текущий стек под именем [name] и возвращает новый набор.
  Future<FavoriteSet> saveCurrentAs(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    final now = _clock().millisecondsSinceEpoch;
    final set = FavoriteSet(
      id: const Uuid().v4(),
      name: trimmed,
      layers: _layers.state.stack,
      createdAt: now,
      updatedAt: now,
    );
    await _store.save(set);
    await loadAll();
    return set;
  }

  /// Заменяет стек слоями набора (прозрачность, цвет, наложение — как
  /// сохранены; порядок пересчитывается). Неизвестный id — [StateError].
  Future<void> apply(String id) async {
    final set = _sets.where((s) => s.id == id).firstOrNull ?? await _store.byId(id);
    if (set == null) throw StateError('No favorite set $id');
    await _layers.replaceAll([...set.layers]..sort((a, b) => a.order.compareTo(b.order)));
  }

  Future<void> remove(String id) async {
    await _store.remove(id);
    await loadAll();
  }

  Future<void> rename(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(newName, 'newName', 'must not be empty');
    final set = await _store.byId(id);
    if (set == null) throw StateError('No favorite set $id');
    await _store.save(set.copyWith(name: trimmed, updatedAt: _clock().millisecondsSinceEpoch));
    await loadAll();
  }
}
