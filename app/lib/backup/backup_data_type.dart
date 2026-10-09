/// Что входит в резервную копию.
enum BackupDataType {
  /// `<корень>/landmarks/`.
  landmarks,

  /// `<корень>/icons/`.
  icons,

  /// `<корень>/maps/`.
  maps,

  /// `<корень>/datastore/maps/` (онлайн-карты, кэш тайлов).
  onDemand,

  /// `<корень>/datastore/dem/`.
  dem,

  /// Все настройки (`settings.json`).
  settings,

  /// Рабочие пространства (`workspaces.json`).
  workspaces,

  /// Избранные наборы слоёв (`favorite_sets.json`).
  favoriteSets,

  /// Оповещения о приближении (`proximity_alerts.json`).
  proximityAlerts;

  /// Папка в архиве для файловых типов; для настроек — null.
  String? get folder => switch (this) {
    landmarks => 'landmarks',
    icons => 'icons',
    maps => 'maps',
    onDemand => 'datastore/maps',
    dem => 'datastore/dem',
    _ => null,
  };

  /// Файл в архиве для типов из настроек; для файловых — null.
  String? get settingsFile => switch (this) {
    settings => 'settings.json',
    workspaces => 'workspaces.json',
    favoriteSets => 'favorite_sets.json',
    proximityAlerts => 'proximity_alerts.json',
    _ => null,
  };

  /// Путь в архиве (папка с `/` в конце или имя файла).
  String get archivePath => folder != null ? '$folder/' : settingsFile!;
}
