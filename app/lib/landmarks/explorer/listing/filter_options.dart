import 'package:app/landmarks/explorer/display/display_state.dart';

import 'item_filter.dart';
import 'landmark_item.dart';

export 'item_filter.dart';

/// Применение [ItemFilter] к списку.
class FilterOptions {
  const FilterOptions({this.filter = const ItemFilter()});

  final ItemFilter filter;

  /// Элементы, прошедшие фильтр, в исходном порядке.
  List<LandmarkItem> apply(List<LandmarkItem> items, {DisplayState display = const DisplayState()}) =>
      filter.isEmpty ? List.of(items) : [for (final i in items) if (filter.matches(i, display: display)) i];
}
