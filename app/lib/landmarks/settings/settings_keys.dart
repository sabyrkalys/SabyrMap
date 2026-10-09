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

  /// Карты: только локальные данные, без сети.
  static const String mapsUseOnlyLocalStorage = 'maps.use_only_local_storage';

  /// Карты: показывать покрытие локальных данных.
  static const String mapsShowLocalCoverage = 'maps.show_local_coverage';

  /// Карты: подкачивать данные высот автоматически.
  static const String mapsAutoDownloadElevation = 'maps.auto_download_elevation';

  /// Карты: окно сведений о карте.
  static const String mapsInformationBox = 'maps.information_box';

  /// Стек слоёв карты, JSON.
  static const String mapsLayerStack = 'maps.layer_stack';

  /// Избранные наборы слоёв, JSON.
  static const String mapsFavoriteSets = 'maps.favorite_sets';

  /// Описания онлайн-карт (AQX), JSON.
  static const String mapsAqxDescriptors = 'maps.aqx_descriptors';

  /// Текущий источник карты (id).
  static const String mapsCurrentSource = 'maps.current_source';

  /// Ширина диапазона стирания цвета по умолчанию.
  static const String mapsColorRangesWidth = 'maps.color_ranges_width';

  /// Настройки данных высот, JSON.
  static const String mapsDemSettings = 'maps.dem.settings';

  /// Сколько дней хранить кэш тайлов.
  static const String mapsOfflineKeepCacheDays = 'maps.offline.keep_cache_days';

  /// Калибровки изображений: путь → точки, JSON.
  static const String mapsCalibrations = 'maps.calibrations';

  /// Закладки проводника: JSON-список путей папок.
  static const String explorerBookmarks = 'explorer.bookmarks';
}
