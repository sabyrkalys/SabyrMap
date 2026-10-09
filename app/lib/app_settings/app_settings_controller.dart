import 'package:app/landmarks/settings/app_settings.dart';
import 'package:flutter/foundation.dart';

import 'app_settings_keys.dart';
import 'app_settings_model.dart';
import 'defaults.dart';

/// Общие настройки приложения. Сеттеры проверяют значение
/// ([ArgumentError]) и сразу сохраняют.
class AppSettingsController extends ChangeNotifier {
  AppSettingsController(this._settings);

  final AppSettings _settings;
  AppSettingsModel _model = const AppSettingsModel();

  AppSettingsModel get model => _model;

  /// Читает настройки; неверные сохранённые значения — по умолчанию.
  Future<void> load() async {
    String pick(String key, String fallback, List<String> allowed) {
      final v = _settings.getString(key);
      return v != null && allowed.contains(v) ? v : fallback;
    }

    final scale = double.tryParse(_settings.getString(AppSettingsKeys.uiScale) ?? '');
    final secondary = _settings.getString(AppSettingsKeys.secondaryCoordsFormat);
    _model = AppSettingsModel(
      locale: pick(AppSettingsKeys.locale, AppDefaults.locale, AppDefaults.supportedLocales),
      darkMode: _bool(AppSettingsKeys.darkMode, AppDefaults.darkMode),
      mapRotationEnabled: _bool(AppSettingsKeys.mapRotationEnabled, AppDefaults.mapRotationEnabled),
      perspectiveEnabled: _bool(AppSettingsKeys.perspectiveEnabled, AppDefaults.perspectiveEnabled),
      lockMapEnabled: _bool(AppSettingsKeys.lockMapEnabled, AppDefaults.lockMapEnabled),
      uiScale: scale != null && _scaleOk(scale) ? scale : AppDefaults.uiScale,
      primaryCoordsFormat: pick(
        AppSettingsKeys.primaryCoordsFormat,
        AppDefaults.primaryCoordsFormat,
        AppDefaults.coordsFormats,
      ),
      secondaryCoordsFormat: AppDefaults.coordsFormats.contains(secondary) ? secondary : null,
      displayGrid: _bool(AppSettingsKeys.displayGrid, AppDefaults.displayGrid),
      displayAltGrid: _bool(AppSettingsKeys.displayAltGrid, AppDefaults.displayAltGrid),
    );
    notifyListeners();
  }

  Future<void> setLocale(String value) async {
    _require(AppDefaults.supportedLocales.contains(value), value, 'locale', 'unsupported locale');
    await _save(AppSettingsKeys.locale, value, _model.copyWith(locale: value));
  }

  Future<void> setDarkMode(bool value) => _save(AppSettingsKeys.darkMode, '$value', _model.copyWith(darkMode: value));

  Future<void> setMapRotationEnabled(bool value) =>
      _save(AppSettingsKeys.mapRotationEnabled, '$value', _model.copyWith(mapRotationEnabled: value));

  Future<void> setPerspectiveEnabled(bool value) =>
      _save(AppSettingsKeys.perspectiveEnabled, '$value', _model.copyWith(perspectiveEnabled: value));

  Future<void> setLockMapEnabled(bool value) =>
      _save(AppSettingsKeys.lockMapEnabled, '$value', _model.copyWith(lockMapEnabled: value));

  /// 0.8..1.5, иначе [ArgumentError].
  Future<void> setUiScale(double value) async {
    _require(_scaleOk(value), value, 'uiScale', 'must be within ${AppDefaults.minUiScale}..${AppDefaults.maxUiScale}');
    await _save(AppSettingsKeys.uiScale, '$value', _model.copyWith(uiScale: value));
  }

  Future<void> setPrimaryCoordsFormat(String value) async {
    _require(AppDefaults.coordsFormats.contains(value), value, 'primaryCoordsFormat', 'must be wgs84 or sk42');
    await _save(AppSettingsKeys.primaryCoordsFormat, value, _model.copyWith(primaryCoordsFormat: value));
  }

  /// null — без второго формата.
  Future<void> setSecondaryCoordsFormat(String? value) async {
    if (value == null) {
      await _settings.remove(AppSettingsKeys.secondaryCoordsFormat);
      _model = _model.copyWith(secondaryCoordsFormat: null);
      notifyListeners();
      return;
    }
    _require(AppDefaults.coordsFormats.contains(value), value, 'secondaryCoordsFormat', 'must be wgs84 or sk42');
    await _save(AppSettingsKeys.secondaryCoordsFormat, value, _model.copyWith(secondaryCoordsFormat: value));
  }

  Future<void> setDisplayGrid(bool value) =>
      _save(AppSettingsKeys.displayGrid, '$value', _model.copyWith(displayGrid: value));

  Future<void> setDisplayAltGrid(bool value) =>
      _save(AppSettingsKeys.displayAltGrid, '$value', _model.copyWith(displayAltGrid: value));

  /// Все общие настройки — по умолчанию (ключи `app.*` удаляются).
  Future<void> reset() async {
    for (final key in [..._settings.keys.where((k) => k.startsWith('app.'))]) {
      await _settings.remove(key);
    }
    _model = const AppSettingsModel();
    notifyListeners();
  }

  static bool _scaleOk(double v) => v >= AppDefaults.minUiScale && v <= AppDefaults.maxUiScale;

  static void _require(bool ok, Object? value, String name, String message) {
    if (!ok) throw ArgumentError.value(value, name, message);
  }

  Future<void> _save(String key, String raw, AppSettingsModel next) async {
    await _settings.setString(key, raw);
    _model = next;
    notifyListeners();
  }

  bool _bool(String key, bool fallback) => switch (_settings.getString(key)) {
    'true' => true,
    'false' => false,
    _ => fallback,
  };
}
