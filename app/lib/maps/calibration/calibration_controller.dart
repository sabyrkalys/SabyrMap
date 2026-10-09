import 'dart:convert';

import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:app/maps/settings/maps_settings.dart';
import 'package:flutter/foundation.dart';

import 'affine_transform.dart';
import 'calibration_point.dart';
import 'calibration_state.dart';

/// Калибровка изображения по 3–4 точкам.
class CalibrationController extends ChangeNotifier {
  CalibrationController(this._settings);

  final MapsSettings _settings;
  CalibrationState _state = const CalibrationState();

  CalibrationState get state => _state;

  /// Начинает калибровку [imagePath]; сохранённые раньше точки подхватываются.
  Future<void> start(String imagePath) async {
    _state = CalibrationState(imagePath: imagePath, isActive: true).copyWith(points: savedPoints(imagePath));
    notifyListeners();
  }

  /// Добавляет точку; пятая — [StateError].
  void addPoint(CalibrationPoint point) {
    _requireActive();
    if (_state.points.length >= CalibrationState.maxPoints) {
      throw StateError('At most ${CalibrationState.maxPoints} calibration points');
    }
    _set(_state.copyWith(points: [..._state.points, point]));
  }

  void removeLastPoint() {
    if (_state.points.isEmpty) return;
    _set(_state.copyWith(points: _state.points.sublist(0, _state.points.length - 1)));
  }

  void updatePoint(int index, CalibrationPoint point) {
    RangeError.checkValidIndex(index, _state.points, 'index');
    _set(_state.copyWith(points: [..._state.points]..[index] = point));
  }

  void setOpacity(double value) => _set(_state.copyWith(opacity: value.clamp(0.0, 1.0)));

  /// Ставит координаты последней точки по центру карты (изображение уже
  /// подвинуто под прицел). Decision: правится последняя поставленная
  /// точка — это та, которую пользователь сейчас наводит.
  void applyScreenCenter(LandmarkLocation world) {
    if (_state.points.isEmpty) return;
    updatePoint(
      _state.points.length - 1,
      _state.points.last.copyWith(worldLon: world.longitude, worldLat: world.latitude),
    );
  }

  /// Считает преобразование, сохраняет точки для изображения и закрывает
  /// калибровку. Меньше 3 точек или точки на одной прямой — [StateError].
  Future<AffineTransform> finish() async {
    _requireActive();
    if (_state.points.length < 3) throw StateError('Calibration needs at least 3 points');
    final transform = AffineTransform.fromThreePoints(_state.points);
    if (transform == null) throw StateError('Calibration points lie on one line');
    final all = _saved()..[_state.imagePath] = [for (final p in _state.points) p.toJson()];
    await _settings.raw.setString(SettingsKeys.mapsCalibrations, jsonEncode(all));
    _set(_state.copyWith(isActive: false));
    return transform;
  }

  /// Закрывает без сохранения.
  void cancel() => _set(const CalibrationState());

  /// Сохранённые точки изображения; нет — пусто.
  List<CalibrationPoint> savedPoints(String imagePath) {
    final raw = _saved()[imagePath];
    if (raw is! List) return const [];
    try {
      return [for (final p in raw) CalibrationPoint.fromJson(p as Map<String, dynamic>)];
    } on Object {
      return const [];
    }
  }

  Map<String, dynamic> _saved() {
    final raw = _settings.raw.getString(SettingsKeys.mapsCalibrations);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.of(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return {};
    }
  }

  void _requireActive() {
    if (!_state.isActive) throw StateError('Calibration is not started');
  }

  void _set(CalibrationState next) {
    _state = next;
    notifyListeners();
  }
}
