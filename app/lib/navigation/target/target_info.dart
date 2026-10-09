/// Сведения о цели относительно исходной точки.
class TargetInfo {
  const TargetInfo({
    required this.distanceMeters,
    required this.azimuthDeg,
    required this.reverseAzimuthDeg,
    this.elevationDiffMeters,
    this.slopePercent,
    this.etaSeconds,
    this.speedMps,
  });

  final double distanceMeters;

  /// Азимут на цель, градусы [0, 360).
  final double azimuthDeg;

  /// Азимут от цели обратно.
  final double reverseAzimuthDeg;

  /// Высота цели минус высота исходной точки.
  final double? elevationDiffMeters;

  /// Уклон, %: 100 × перепад / расстояние.
  final double? slopePercent;

  /// Время в пути при текущей скорости.
  final int? etaSeconds;
  final double? speedMps;
}
