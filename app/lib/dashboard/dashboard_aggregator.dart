import 'package:app/landmarks/explorer/listing/landmark_item.dart';

import 'activity_breakdown.dart';
import 'dashboard_snapshot.dart';
import 'year_breakdown.dart';

/// Сводка по элементам списка. Нет значения у элемента — в сумму не
/// входит; год — [LandmarkItem.year] или год создания; активность без
/// названия — [unknownActivity].
class DashboardAggregator {
  const DashboardAggregator();

  static const String unknownActivity = 'unknown';

  DashboardSnapshot aggregate(List<LandmarkItem> items) => DashboardSnapshot(
    totalItems: items.length,
    totalLengthMeters: items.fold(0.0, (s, i) => s + (i.lengthMeters ?? 0)),
    totalDurationMs: items.fold(0, (s, i) => s + (i.durationMs ?? 0)),
    totalGainMeters: items.fold(0.0, (s, i) => s + (i.elevationGainMeters ?? 0)),
    totalLossMeters: items.fold(0.0, (s, i) => s + (i.elevationLossMeters ?? 0)),
    totalAreaSquareMeters: items.fold(0.0, (s, i) => s + (i.areaSquareMeters ?? 0)),
    yearCount: {for (final i in items) i.effectiveYear}.length,
    activityCount: {for (final i in items) i.activity ?? unknownActivity}.length,
  );

  /// По годам, от раннего к позднему.
  List<YearBreakdown> byYear(List<LandmarkItem> items) {
    final out = <int, YearBreakdown>{};
    for (final i in items) {
      final prev = out[i.effectiveYear] ?? YearBreakdown(year: i.effectiveYear);
      out[i.effectiveYear] = YearBreakdown(
        year: prev.year,
        lengthMeters: prev.lengthMeters + (i.lengthMeters ?? 0),
        durationMs: prev.durationMs + (i.durationMs ?? 0),
        itemCount: prev.itemCount + 1,
      );
    }
    return [for (final y in out.keys.toList()..sort()) out[y]!];
  }

  /// По видам активности, от большей длины к меньшей (при равной — по имени).
  List<ActivityBreakdown> byActivity(List<LandmarkItem> items) {
    final out = <String, ActivityBreakdown>{};
    for (final i in items) {
      final key = i.activity ?? unknownActivity;
      final prev = out[key] ?? ActivityBreakdown(activity: key);
      out[key] = ActivityBreakdown(
        activity: key,
        lengthMeters: prev.lengthMeters + (i.lengthMeters ?? 0),
        itemCount: prev.itemCount + 1,
      );
    }
    return out.values.toList()
      ..sort((a, b) {
        final byLength = b.lengthMeters.compareTo(a.lengthMeters);
        return byLength != 0 ? byLength : a.activity.compareTo(b.activity);
      });
  }
}
