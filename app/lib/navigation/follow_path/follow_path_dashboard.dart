/// Панель следования по треку.
class FollowPathDashboard {
  const FollowPathDashboard({
    required this.remainingDistanceMeters,
    this.remainingGainMeters = 0,
    this.remainingLossMeters = 0,
    this.etaSeconds,
    this.distanceToTrackMeters,
    this.currentSegmentIndex,
  });

  /// Длина трека от текущей точки до конца.
  final double remainingDistanceMeters;
  final double remainingGainMeters;
  final double remainingLossMeters;
  final int? etaSeconds;

  /// Отклонение от трека; null — положение неизвестно.
  final double? distanceToTrackMeters;
  final int? currentSegmentIndex;
}
