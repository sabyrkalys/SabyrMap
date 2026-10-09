import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';

/// Настройки навигации поверх [AppSettings] (значения хранятся строками).
class NavigationSettings {
  NavigationSettings(this._settings);

  final AppSettings _settings;

  static const double defaultDeviationThreshold = 50.0;
  static const String defaultWorkspace = 'default';

  bool get targetDisplayLine => _bool(SettingsKeys.targetDisplayLine, true);
  Future<void> setTargetDisplayLine(bool value) => _settings.setString(SettingsKeys.targetDisplayLine, '$value');

  bool get targetDisplayInfoBox => _bool(SettingsKeys.targetDisplayInfoBox, true);
  Future<void> setTargetDisplayInfoBox(bool value) => _settings.setString(SettingsKeys.targetDisplayInfoBox, '$value');

  double get followPathDeviationThreshold {
    final v = double.tryParse(_settings.getString(SettingsKeys.followPathDeviationThreshold) ?? '');
    return v != null && v > 0 ? v : defaultDeviationThreshold;
  }

  Future<void> setFollowPathDeviationThreshold(double value) {
    if (!(value > 0)) throw ArgumentError.value(value, 'value', 'must be positive');
    return _settings.setString(SettingsKeys.followPathDeviationThreshold, '$value');
  }

  bool get signalsEnabled => _bool(SettingsKeys.signalsEnabled, true);
  Future<void> setSignalsEnabled(bool value) => _settings.setString(SettingsKeys.signalsEnabled, '$value');

  String get currentWorkspace => _settings.getString(SettingsKeys.currentWorkspace) ?? defaultWorkspace;
  Future<void> setCurrentWorkspace(String id) => _settings.setString(SettingsKeys.currentWorkspace, id);

  bool _bool(String key, bool fallback) => switch (_settings.getString(key)) {
    'true' => true,
    'false' => false,
    _ => fallback,
  };
}
