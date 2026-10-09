import 'package:app/landmarks/explorer/listing/landmark_item.dart';

import 'list_statistics.dart';

/// Итоги по списку: суммы и разбивка по годам и видам активности.
/// Отсутствующие значения (null) в суммы не входят.
class StatisticsCalculator {
  const StatisticsCalculator();

  /// Вид активности для элементов без него.
  static const String unknownActivity = 'unknown';

  ListStatistics calculate(List<LandmarkItem> items) {
    var length = 0.0;
    var duration = 0;
    var gain = 0.0;
    var area = 0.0;
    for (final item in items) {
      length += item.lengthMeters ?? 0;
      duration += item.durationMs ?? 0;
      gain += item.elevationGainMeters ?? 0;
      area += item.areaSquareMeters ?? 0;
    }
    return ListStatistics(
      itemCount: items.length,
      totalLengthMeters: length,
      totalDurationMs: duration,
      totalElevationGainMeters: gain,
      totalAreaSquareMeters: area,
      lengthByYear: lengthByYear(items),
      durationByYear: durationByYear(items),
      lengthByActivity: lengthByActivity(items),
    );
  }

  /// Длина по годам ([LandmarkItem.effectiveYear]); только элементы с длиной.
  Map<int, double> lengthByYear(List<LandmarkItem> items) {
    final out = <int, double>{};
    for (final item in items) {
      final l = item.lengthMeters;
      if (l != null) out.update(item.effectiveYear, (v) => v + l, ifAbsent: () => l);
    }
    return out;
  }

  /// Длительность по годам; только элементы с длительностью.
  Map<int, int> durationByYear(List<LandmarkItem> items) {
    final out = <int, int>{};
    for (final item in items) {
      final d = item.durationMs;
      if (d != null) out.update(item.effectiveYear, (v) => v + d, ifAbsent: () => d);
    }
    return out;
  }

  /// Длина по видам активности (без вида — [unknownActivity]); только
  /// элементы с длиной.
  Map<String, double> lengthByActivity(List<LandmarkItem> items) {
    final out = <String, double>{};
    for (final item in items) {
      final l = item.lengthMeters;
      if (l != null) out.update(item.activity ?? unknownActivity, (v) => v + l, ifAbsent: () => l);
    }
    return out;
  }

}
