/// Ключи настроек sabyrmap в [AppSettings].
abstract final class SettingsKeys {
  /// Папка, куда по умолчанию сохраняются новые метки.
  static const String defaultFolder = 'landmarks.default_folder';

  /// Папка, открытая сейчас в проводнике меток.
  static const String currentFolder = 'landmarks.current_folder';

  /// Режим вида проводника; дальше — отпечаток пути папки.
  static const String viewModePrefix = 'explorer.view_mode.';

  /// Сортировка проводника; дальше — область (`global`).
  static const String sortPrefix = 'explorer.sort.';

  /// Фильтр проводника; дальше — область (`global`).
  static const String filterPrefix = 'explorer.filter.';

  /// Объекты на карте; дальше — id рабочего пространства. JSON-список путей.
  static const String displayedPrefix = 'explorer.displayed.';
}
