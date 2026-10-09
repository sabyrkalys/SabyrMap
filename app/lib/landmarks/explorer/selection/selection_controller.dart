import 'package:flutter/foundation.dart';

import 'selection_state.dart';

/// Выбор файлов в проводнике. Сообщает слушателям о каждом изменении.
class SelectionController extends ChangeNotifier {
  SelectionState _state = const SelectionState();

  SelectionState get state => _state;

  /// Включить мультивыбор (долгое нажатие в режиме превью).
  void activate() => _set(_state.activate());

  /// Выключить мультивыбор; выбор снимается.
  void deactivate() => _set(_state.deactivate());

  /// «Выбрать все» в режиме списка.
  void selectAll(Iterable<String> paths) => _set(_state.selectAll(paths));

  /// «Снять выбор».
  void clear() => _set(_state.clear());

  void toggle(String path) => _set(_state.toggle(path));
  void select(String path) => _set(_state.select(path));
  void deselect(String path) => _set(_state.deselect(path));

  bool contains(String path) => _state.contains(path);

  /// Неизменяемая копия выбранных путей для операции.
  Set<String> snapshot() => Set.unmodifiable(_state.selectedPaths);

  void _set(SelectionState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }
}
