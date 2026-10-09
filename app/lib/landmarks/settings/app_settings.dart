import 'package:shared_preferences/shared_preferences.dart';

/// Настройки приложения поверх [SharedPreferences].
class AppSettings {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  Future<void> remove(String key) => _prefs.remove(key);
}
