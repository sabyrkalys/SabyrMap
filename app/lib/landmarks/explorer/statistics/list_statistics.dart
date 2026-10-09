import 'package:collection/collection.dart';

/// Итоги по списку проводника.
class ListStatistics {
  const ListStatistics({
    this.itemCount = 0,
    this.totalLengthMeters = 0,
    this.totalDurationMs = 0,
    this.totalElevationGainMeters = 0,
    this.totalAreaSquareMeters = 0,
    this.lengthByYear = const {},
    this.durationByYear = const {},
    this.lengthByActivity = const {},
  });

  final int itemCount;
  final double totalLengthMeters;
  final int totalDurationMs;
  final double totalElevationGainMeters;
  final double totalAreaSquareMeters;

  final Map<int, double> lengthByYear;
  final Map<int, int> durationByYear;
  final Map<String, double> lengthByActivity;

  static const _map = MapEquality<Object, num>();

  @override
  bool operator ==(Object other) =>
      other is ListStatistics &&
      other.itemCount == itemCount &&
      other.totalLengthMeters == totalLengthMeters &&
      other.totalDurationMs == totalDurationMs &&
      other.totalElevationGainMeters == totalElevationGainMeters &&
      other.totalAreaSquareMeters == totalAreaSquareMeters &&
      _map.equals(other.lengthByYear, lengthByYear) &&
      _map.equals(other.durationByYear, durationByYear) &&
      _map.equals(other.lengthByActivity, lengthByActivity);

  @override
  int get hashCode => Object.hash(
    itemCount,
    totalLengthMeters,
    totalDurationMs,
    totalElevationGainMeters,
    totalAreaSquareMeters,
    _map.hash(lengthByYear),
    _map.hash(durationByYear),
    _map.hash(lengthByActivity),
  );
}
