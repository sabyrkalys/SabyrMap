import 'listing/landmark_item.dart';

/// Строка проводника: папка или файл метки.
sealed class ExplorerNode {
  const ExplorerNode({required this.path, required this.name});

  final String path;
  final String name;
}

/// Подпапка.
class ExplorerFolderNode extends ExplorerNode {
  const ExplorerFolderNode({required super.path, required super.name, this.childCount = unknownCount});

  /// Значение [childCount], пока содержимое не читали.
  static const int unknownCount = -1;

  /// Сколько элементов внутри; [unknownCount] — не читали.
  final int childCount;

  @override
  bool operator ==(Object other) =>
      other is ExplorerFolderNode && other.path == path && other.name == name && other.childCount == childCount;

  @override
  int get hashCode => Object.hash(path, name, childCount);
}

/// Файл метки.
class ExplorerItemNode extends ExplorerNode {
  ExplorerItemNode(this.item) : super(path: item.path, name: item.name);

  final LandmarkItem item;

  @override
  bool operator ==(Object other) => other is ExplorerItemNode && other.item == item;

  @override
  int get hashCode => item.hashCode;
}
