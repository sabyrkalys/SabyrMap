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

  /// Линия к цели.
  static const String targetDisplayLine = 'navigation.target.display_line';

  /// Окно сведений о цели.
  static const String targetDisplayInfoBox = 'navigation.target.display_info_box';

  /// Порог отклонения от трека, метры.
  static const String followPathDeviationThreshold = 'navigation.follow_path.deviation_threshold';

  /// Звуковые сигналы навигации.
  static const String signalsEnabled = 'navigation.signals.enabled';

  /// Оповещения о приближении; дальше — id рабочего пространства.
  static const String proximityPrefix = 'navigation.proximity.';

  /// Текущее рабочее пространство.
  static const String currentWorkspace = 'navigation.current_workspace';
}
