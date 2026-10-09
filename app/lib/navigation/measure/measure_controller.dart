import 'package:app/landmarks/models/landmark_location.dart';
import 'package:flutter/foundation.dart';

import 'measure_calculator.dart';
import 'measure_state.dart';

/// Измерение расстояний по точкам.
class MeasureController extends ChangeNotifier {
  MeasureState _state = const MeasureState();

  MeasureState get state => _state;

  /// Добавляет точку и открывает панель.
  void addPoint(LandmarkLocation location) => _set([..._state.points, location], visible: true);

  void removeLast() {
    if (_state.points.isEmpty) return;
    _set(_state.points.sublist(0, _state.points.length - 1), visible: _state.panelVisible);
  }

  /// Удаляет измерение и закрывает панель.
  void clear() {
    _state = const MeasureState();
    notifyListeners();
  }

  /// Скрывает панель; измерение остаётся на карте до [clear].
  void close() => _setVisible(false);

  /// Показывает панель.
  void reopen() => _setVisible(true);

  void _setVisible(bool visible) {
    if (visible == _state.panelVisible) return;
    _state = MeasureState(
      points: _state.points,
      segments: _state.segments,
      totalDistanceMeters: _state.totalDistanceMeters,
      panelVisible: visible,
    );
    notifyListeners();
  }

  void _set(List<LandmarkLocation> points, {required bool visible}) {
    _state = MeasureState(
      points: List.unmodifiable(points),
      segments: List.unmodifiable(MeasureCalculator.buildSegments(points)),
      totalDistanceMeters: MeasureCalculator.totalDistance(points),
      panelVisible: visible,
    );
    notifyListeners();
  }
}
