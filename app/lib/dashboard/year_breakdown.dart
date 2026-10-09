/// Итоги за год.
class YearBreakdown {
  const YearBreakdown({required this.year, this.lengthMeters = 0, this.durationMs = 0, this.itemCount = 0});

  final int year;
  final double lengthMeters;
  final int durationMs;
  final int itemCount;

  @override
  bool operator ==(Object other) =>
      other is YearBreakdown &&
      other.year == year &&
      other.lengthMeters == lengthMeters &&
      other.durationMs == durationMs &&
      other.itemCount == itemCount;

  @override
  int get hashCode => Object.hash(year, lengthMeters, durationMs, itemCount);

  @override
  String toString() => 'YearBreakdown($year, $lengthMeters m, $durationMs ms, $itemCount)';
}
