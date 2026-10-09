import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/services/waypoint_service.dart';
import 'package:app/navigation/position/position_source.dart';
import 'package:flutter/foundation.dart';

import 'target_calculator.dart';
import 'target_state.dart';

/// Цель навигации: точка, к которой тянется линия, и сведения о ней.
///
/// Decision: исходная точка — последний центр экрана из [updateSource];
/// [refresh] берёт её из положения устройства, если оно известно (тогда
/// же появляется время в пути). [WaypointService] нужен, чтобы
/// [setTargetFromWaypoint] мог прочитать файл точки.
class TargetController extends ChangeNotifier {
  TargetController(
    this._position, {
    required WaypointService waypoints,
    bool displayLine = true,
    bool displayInfoBox = true,
  }) : _waypoints = waypoints,
       _state = TargetState(displayLine: displayLine, displayInfoBox: displayInfoBox);

  final PositionSource _position;
  final WaypointService _waypoints;
  TargetState _state;
  double? _speedMps;

  TargetState get state => _state;

  /// Ставит цель и считает сведения от известной исходной точки (или от
  /// положения устройства).
  Future<void> setTarget(LandmarkLocation target) async {
    var source = _state.source;
    if (source == null) {
      final position = await _position.getCurrent();
      if (position != null && position.isValid) {
        source = position.location;
        _speedMps = position.speedMps;
      }
    }
    _emit(target: target, source: source);
  }

  /// Цель — путевая точка из файла.
  Future<void> setTargetFromWaypoint(String filePath) async =>
      setTarget((await _waypoints.load(filePath)).location);

  /// Снимает цель вместе со сведениями.
  Future<void> removeTarget() async {
    if (!_state.isActive) return;
    _state = TargetState(displayLine: _state.displayLine, displayInfoBox: _state.displayInfoBox);
    _speedMps = null;
    notifyListeners();
  }

  /// Куда прокрутить карту; без цели — null.
  Future<LandmarkLocation?> jumpToTarget() async => _state.target;

  /// Новая исходная точка (центр экрана). Без цели запоминается молча.
  void updateSource(LandmarkLocation source) {
    if (!_state.isActive) {
      _state = TargetState(source: source, displayLine: _state.displayLine, displayInfoBox: _state.displayInfoBox);
      return;
    }
    _speedMps = null;
    _emit(target: _state.target!, source: source);
  }

  void setDisplayLine(bool value) {
    if (value == _state.displayLine) return;
    _state = TargetState(
      target: _state.target,
      source: _state.source,
      info: _state.info,
      displayLine: value,
      displayInfoBox: _state.displayInfoBox,
    );
    notifyListeners();
  }

  void setDisplayInfoBox(bool value) {
    if (value == _state.displayInfoBox) return;
    _state = TargetState(
      target: _state.target,
      source: _state.source,
      info: _state.info,
      displayLine: _state.displayLine,
      displayInfoBox: value,
    );
    notifyListeners();
  }

  /// Пересчёт от текущего положения устройства (если оно известно).
  Future<void> refresh() async {
    final target = _state.target;
    if (target == null) return;
    final position = await _position.getCurrent();
    if (position != null && position.isValid) {
      _speedMps = position.speedMps;
      _emit(target: target, source: position.location);
    } else {
      _emit(target: target, source: _state.source);
    }
  }

  void _emit({required LandmarkLocation target, LandmarkLocation? source}) {
    _state = TargetState(
      target: target,
      source: source,
      info: source == null
          ? null
          : TargetCalculator.compute(
              source: source,
              target: target,
              sourceElevation: TargetCalculator.elevationOf(source),
              targetElevation: TargetCalculator.elevationOf(target),
              speedMps: _speedMps,
            ),
      displayLine: _state.displayLine,
      displayInfoBox: _state.displayInfoBox,
    );
    notifyListeners();
  }
}
