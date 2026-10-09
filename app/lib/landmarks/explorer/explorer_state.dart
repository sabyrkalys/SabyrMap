import 'package:collection/collection.dart';

import 'explorer_node.dart';
import 'explorer_view_mode.dart';
import 'listing/item_filter.dart';
import 'listing/sort_options.dart';
import 'places/place_root.dart';

/// Состояние проводника. Неизменяемое; меняется через [copyWith].
class ExplorerState {
  const ExplorerState({
    this.currentPlace,
    this.currentFolder,
    this.nodes = const [],
    this.viewMode = ExplorerViewMode.preview,
    this.sort = const SortOptions(),
    this.filter = const ItemFilter(),
    this.isLoading = false,
    this.errorMessage,
  });

  final PlaceRoot? currentPlace;
  final String? currentFolder;

  /// Папки (по имени), затем метки — отфильтрованные и отсортированные.
  final List<ExplorerNode> nodes;
  final ExplorerViewMode viewMode;

  /// Выбранная пользователем сортировка (может ждать центра экрана).
  final SortOptions sort;
  final ItemFilter filter;
  final bool isLoading;
  final String? errorMessage;

  static const Object _keep = Object();

  /// Копия с заменёнными полями; для [currentPlace], [currentFolder] и
  /// [errorMessage] явный null очищает значение.
  ExplorerState copyWith({
    Object? currentPlace = _keep,
    Object? currentFolder = _keep,
    List<ExplorerNode>? nodes,
    ExplorerViewMode? viewMode,
    SortOptions? sort,
    ItemFilter? filter,
    bool? isLoading,
    Object? errorMessage = _keep,
  }) => ExplorerState(
    currentPlace: identical(currentPlace, _keep) ? this.currentPlace : currentPlace as PlaceRoot?,
    currentFolder: identical(currentFolder, _keep) ? this.currentFolder : currentFolder as String?,
    nodes: nodes ?? this.nodes,
    viewMode: viewMode ?? this.viewMode,
    sort: sort ?? this.sort,
    filter: filter ?? this.filter,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: identical(errorMessage, _keep) ? this.errorMessage : errorMessage as String?,
  );

  static const _nodes = ListEquality<ExplorerNode>();

  @override
  bool operator ==(Object other) =>
      other is ExplorerState &&
      other.currentPlace == currentPlace &&
      other.currentFolder == currentFolder &&
      _nodes.equals(other.nodes, nodes) &&
      other.viewMode == viewMode &&
      other.sort == sort &&
      other.filter == filter &&
      other.isLoading == isLoading &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode =>
      Object.hash(currentPlace, currentFolder, _nodes.hash(nodes), viewMode, sort, filter, isLoading, errorMessage);
}
