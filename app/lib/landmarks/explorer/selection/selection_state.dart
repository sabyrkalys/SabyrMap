import 'package:collection/collection.dart';

/// Выбранные в проводнике файлы и включён ли режим выбора.
class SelectionState {
  const SelectionState({this.selectedPaths = const {}, this.isActive = false});

  final Set<String> selectedPaths;

  /// Режим мультивыбора включён.
  final bool isActive;

  int get count => selectedPaths.length;
  bool contains(String path) => selectedPaths.contains(path);

  SelectionState select(String path) => contains(path) ? this : _with({...selectedPaths, path});

  SelectionState deselect(String path) => contains(path) ? _with({...selectedPaths}..remove(path)) : this;

  SelectionState toggle(String path) => contains(path) ? deselect(path) : select(path);

  SelectionState selectAll(Iterable<String> paths) => _with({...selectedPaths, ...paths});

  SelectionState clear() => _with(const {});

  SelectionState activate() => SelectionState(selectedPaths: selectedPaths, isActive: true);

  /// Выключает режим и снимает выбор.
  SelectionState deactivate() => const SelectionState();

  SelectionState _with(Set<String> paths) => SelectionState(selectedPaths: Set.unmodifiable(paths), isActive: isActive);

  static const _set = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is SelectionState && other.isActive == isActive && _set.equals(other.selectedPaths, selectedPaths);

  @override
  int get hashCode => Object.hash(isActive, _set.hash(selectedPaths));
}
