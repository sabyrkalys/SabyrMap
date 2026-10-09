import 'package:app/landmarks/models/landmark_location.dart';

import 'measure_segment.dart';

/// Измерение на карте.
class MeasureState {
  const MeasureState({
    this.points = const [],
    this.segments = const [],
    this.totalDistanceMeters = 0,
    this.panelVisible = false,
  });

  final List<LandmarkLocation> points;
  final List<MeasureSegment> segments;
  final double totalDistanceMeters;

  /// Панель измерения открыта.
  final bool panelVisible;

  /// Панель открыта (закрытое измерение остаётся на карте).
  bool get isActive => panelVisible;

  /// Есть что показать на карте.
  bool get hasMeasurement => points.isNotEmpty;
}
