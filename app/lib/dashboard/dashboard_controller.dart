import 'dart:math';

import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/explorer/listing/landmark_item_reader.dart';
import 'package:flutter/foundation.dart';

import 'activity_breakdown.dart';
import 'dashboard_aggregator.dart';
import 'dashboard_snapshot.dart';
import 'year_breakdown.dart';

/// Дашборд статистики по выбранным файлам меток.
///
/// Decision: файлы читаются через [LandmarkItemReader] (заголовок и
/// метаданные, без содержимого); репозиторий для этого не нужен.
class DashboardController extends ChangeNotifier {
  DashboardController(this._reader, {DashboardAggregator aggregator = const DashboardAggregator()})
    : _aggregator = aggregator;

  final LandmarkItemReader _reader;
  final DashboardAggregator _aggregator;

  DashboardSnapshot? _snapshot;
  List<YearBreakdown> _years = const [];
  List<ActivityBreakdown> _activities = const [];
  bool _loading = false;
  int _token = 0;

  DashboardSnapshot? get snapshot => _snapshot;
  List<YearBreakdown> get years => _years;
  List<ActivityBreakdown> get activities => _activities;
  bool get isLoading => _loading;

  /// Пересчитывает по файлам [itemPaths]; нечитаемые пропускаются.
  Future<void> refresh(List<String> itemPaths) async {
    final token = ++_token;
    _loading = true;
    notifyListeners();
    final items = <LandmarkItem>[];
    for (var start = 0; start < itemPaths.length; start += LandmarkItemReader.maxParallelReads) {
      final chunk = itemPaths.sublist(start, min(start + LandmarkItemReader.maxParallelReads, itemPaths.length));
      items.addAll((await Future.wait(chunk.map(_reader.read))).whereType<LandmarkItem>());
    }
    if (token != _token) return;
    _snapshot = _aggregator.aggregate(items);
    _years = List.unmodifiable(_aggregator.byYear(items));
    _activities = List.unmodifiable(_aggregator.byActivity(items));
    _loading = false;
    notifyListeners();
  }

  void clear() {
    _token++;
    _snapshot = null;
    _years = const [];
    _activities = const [];
    _loading = false;
    notifyListeners();
  }
}
