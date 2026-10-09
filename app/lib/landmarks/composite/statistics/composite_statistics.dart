/// Итоги составного объекта.
class CompositeStatistics {
  const CompositeStatistics({
    this.totalLengthMeters = 0,
    this.durationMs,
    this.elevationGainMeters = 0,
    this.elevationLossMeters = 0,
    this.minElevationMeters,
    this.maxElevationMeters,
    this.areaSquareMeters,
    this.perimeterMeters,
  });

  /// Длина пути (у области — периметр), метры.
  final double totalLengthMeters;

  /// Длительность трека; null — нет времени у точек.
  final int? durationMs;
  final double elevationGainMeters;
  final double elevationLossMeters;
  final double? minElevationMeters;
  final double? maxElevationMeters;

  /// Только у области.
  final double? areaSquareMeters;
  final double? perimeterMeters;

  @override
  bool operator ==(Object other) =>
      other is CompositeStatistics &&
      other.totalLengthMeters == totalLengthMeters &&
      other.durationMs == durationMs &&
      other.elevationGainMeters == elevationGainMeters &&
      other.elevationLossMeters == elevationLossMeters &&
      other.minElevationMeters == minElevationMeters &&
      other.maxElevationMeters == maxElevationMeters &&
      other.areaSquareMeters == areaSquareMeters &&
      other.perimeterMeters == perimeterMeters;

  @override
  int get hashCode => Object.hash(
    totalLengthMeters,
    durationMs,
    elevationGainMeters,
    elevationLossMeters,
    minElevationMeters,
    maxElevationMeters,
    areaSquareMeters,
    perimeterMeters,
  );

  @override
  String toString() =>
      'CompositeStatistics(length: $totalLengthMeters, duration: $durationMs, gain: $elevationGainMeters, '
      'loss: $elevationLossMeters, area: $areaSquareMeters, perimeter: $perimeterMeters)';
}
