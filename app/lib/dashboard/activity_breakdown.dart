/// Итоги по виду активности.
class ActivityBreakdown {
  const ActivityBreakdown({required this.activity, this.lengthMeters = 0, this.itemCount = 0});

  final String activity;
  final double lengthMeters;
  final int itemCount;

  @override
  bool operator ==(Object other) =>
      other is ActivityBreakdown &&
      other.activity == activity &&
      other.lengthMeters == lengthMeters &&
      other.itemCount == itemCount;

  @override
  int get hashCode => Object.hash(activity, lengthMeters, itemCount);

  @override
  String toString() => 'ActivityBreakdown($activity, $lengthMeters m, $itemCount)';
}
