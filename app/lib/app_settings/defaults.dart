/// Значения общих настроек по умолчанию и допустимые значения.
abstract final class AppDefaults {
  static const String locale = 'ru';
  static const List<String> supportedLocales = ['ru', 'en'];
  static const bool darkMode = false;
  static const bool mapRotationEnabled = true;
  static const bool perspectiveEnabled = false;
  static const bool lockMapEnabled = false;
  static const double uiScale = 1.0;
  static const double minUiScale = 0.8;
  static const double maxUiScale = 1.5;
  static const String primaryCoordsFormat = 'wgs84';
  static const List<String> coordsFormats = ['wgs84', 'sk42'];
  static const bool displayGrid = false;
  static const bool displayAltGrid = false;
}
