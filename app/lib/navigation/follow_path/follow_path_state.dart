import 'package:app/landmarks/models/landmark_track.dart';

import 'follow_path_dashboard.dart';

/// Состояние следования по треку.
class FollowPathState {
  const FollowPathState({
    this.trackPath,
    this.track,
    this.currentSegmentIndex = 0,
    this.currentPointIndex = 0,
    this.reverseOrder = false,
    this.loop = false,
    this.autoTargetDistanceMeters,
    this.deviationThresholdMeters = defaultThreshold,
    this.deviationSignaled = false,
    this.dashboard,
    this.errorMessage,
  });

  static const double defaultThreshold = 50.0;

  final String? trackPath;

  /// Трек в порядке следования (уже развёрнутый при [reverseOrder]).
  final TrackObject? track;
  final int currentSegmentIndex;

  /// Ближайшая точка в текущем сегменте.
  final int currentPointIndex;
  final bool reverseOrder;
  final bool loop;

  /// Расстояние до автоматической цели впереди; null — без неё.
  final double? autoTargetDistanceMeters;
  final double deviationThresholdMeters;

  /// Подаётся ли сейчас сигнал отклонения.
  final bool deviationSignaled;
  final FollowPathDashboard? dashboard;
  final String? errorMessage;

  bool get isActive => track != null;

  static const Object _keep = Object();

  FollowPathState copyWith({
    int? currentSegmentIndex,
    int? currentPointIndex,
    bool? reverseOrder,
    bool? loop,
    Object? autoTargetDistanceMeters = _keep,
    double? deviationThresholdMeters,
    bool? deviationSignaled,
    Object? dashboard = _keep,
    TrackObject? track,
  }) => FollowPathState(
    trackPath: trackPath,
    track: track ?? this.track,
    currentSegmentIndex: currentSegmentIndex ?? this.currentSegmentIndex,
    currentPointIndex: currentPointIndex ?? this.currentPointIndex,
    reverseOrder: reverseOrder ?? this.reverseOrder,
    loop: loop ?? this.loop,
    autoTargetDistanceMeters: identical(autoTargetDistanceMeters, _keep)
        ? this.autoTargetDistanceMeters
        : autoTargetDistanceMeters as double?,
    deviationThresholdMeters: deviationThresholdMeters ?? this.deviationThresholdMeters,
    deviationSignaled: deviationSignaled ?? this.deviationSignaled,
    dashboard: identical(dashboard, _keep) ? this.dashboard : dashboard as FollowPathDashboard?,
    errorMessage: errorMessage,
  );
}
