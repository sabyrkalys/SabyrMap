/// Итоги по списку объектов.
class DashboardSnapshot {
  const DashboardSnapshot({
    this.totalItems = 0,
    this.totalLengthMeters = 0,
    this.totalDurationMs = 0,
    this.totalGainMeters = 0,
    this.totalLossMeters = 0,
    this.totalAreaSquareMeters = 0,
    this.yearCount = 0,
    this.activityCount = 0,
  });

  final int totalItems;
  final double totalLengthMeters;
  final int totalDurationMs;
  final double totalGainMeters;
  final double totalLossMeters;
  final double totalAreaSquareMeters;
  final int yearCount;
  final int activityCount;

  @override
  bool operator ==(Object other) =>
      other is DashboardSnapshot &&
      other.totalItems == totalItems &&
      other.totalLengthMeters == totalLengthMeters &&
      other.totalDurationMs == totalDurationMs &&
      other.totalGainMeters == totalGainMeters &&
      other.totalLossMeters == totalLossMeters &&
      other.totalAreaSquareMeters == totalAreaSquareMeters &&
      other.yearCount == yearCount &&
      other.activityCount == activityCount;

  @override
  int get hashCode => Object.hash(
    totalItems,
    totalLengthMeters,
    totalDurationMs,
    totalGainMeters,
    totalLossMeters,
    totalAreaSquareMeters,
    yearCount,
    activityCount,
  );
}
