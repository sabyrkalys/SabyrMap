import 'package:collection/collection.dart';

/// Какие файлы меток показаны на карте (по путям).
class DisplayState {
  const DisplayState({this.displayedPaths = const {}});

  final Set<String> displayedPaths;

  bool isDisplayed(String path) => displayedPaths.contains(path);

  DisplayState withDisplayed(String path) =>
      isDisplayed(path) ? this : DisplayState(displayedPaths: Set.unmodifiable({...displayedPaths, path}));

  DisplayState withUndisplayed(String path) => isDisplayed(path)
      ? DisplayState(displayedPaths: Set.unmodifiable({...displayedPaths}..remove(path)))
      : this;

  DisplayState toggle(String path) => isDisplayed(path) ? withUndisplayed(path) : withDisplayed(path);

  bool get isEmpty => displayedPaths.isEmpty;
  int get count => displayedPaths.length;

  static const _set = SetEquality<String>();

  @override
  bool operator ==(Object other) => other is DisplayState && _set.equals(other.displayedPaths, displayedPaths);

  @override
  int get hashCode => _set.hash(displayedPaths);
}
