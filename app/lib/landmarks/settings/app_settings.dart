import 'package:shared_preferences/shared_preferences.dart';

/// Настройки приложения поверх [SharedPreferences].
class AppSettings {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  /// Все ключи настроек.
  Set<String> get keys => _prefs.getKeys();

  /// Все настройки как есть: значения String, bool, int, double или
  /// `List<String>`.
  Map<String, Object> exportAll() => {
    for (final key in _prefs.getKeys())
      if (_prefs.get(key) case final Object value) key: value,
  };

  /// Записывает [values] (типы как в [exportAll]); значение другого типа —
  /// [ArgumentError].
  Future<void> importAll(Map<String, Object?> values) async {
    for (final MapEntry(:key, :value) in values.entries) {
      switch (value) {
        case final String v:
          await _prefs.setString(key, v);
        case final bool v:
          await _prefs.setBool(key, v);
        case final int v:
          await _prefs.setInt(key, v);
        case final double v:
          await _prefs.setDouble(key, v);
        case final List<dynamic> v when v.every((e) => e is String):
          await _prefs.setStringList(key, v.cast<String>());
        default:
          throw ArgumentError.value(value, key, 'unsupported settings value');
      }
    }
  }
}
