import 'package:app/landmarks/settings/settings_keys.dart';

/// Сводка ключей настроек всех слоёв sabyrmap.
///
/// - `landmarks.*` — хранилище и папки меток;
/// - `explorer.*` — проводник меток;
/// - `navigation.*` — навигация;
/// - `maps.*` — карты и слои;
/// - `workspace.*` — рабочие пространства;
/// - `app.*` — общие настройки приложения.
/// Отдельные ключи первых слоёв — в [SettingsKeys].
abstract final class AppSettingsKeys {
  static const String locale = 'app.locale';
  static const String darkMode = 'app.dark_mode';
  static const String mapRotationEnabled = 'app.map_rotation';
  static const String perspectiveEnabled = 'app.perspective';
  static const String lockMapEnabled = 'app.lock_map';
  static const String uiScale = 'app.ui_scale';
  static const String primaryCoordsFormat = 'app.coords.primary';
  static const String secondaryCoordsFormat = 'app.coords.secondary';
  static const String displayGrid = 'app.grid';
  static const String displayAltGrid = 'app.alt_grid';

  static const String workspaceList = 'workspace.list';
  static const String workspaceActive = 'workspace.active';
  static const String workspaceSnapshotPrefix = 'workspace.snapshot.';

  /// Префиксы групп ключей.
  static const List<String> prefixes = ['landmarks.', 'explorer.', 'navigation.', 'maps.', 'workspace.', 'app.'];

  /// Ключи рабочих пространств.
  static bool isWorkspaceKey(String key) => key.startsWith('workspace.');

  /// Ключи избранных наборов карт.
  static bool isFavoriteSetsKey(String key) => key == SettingsKeys.mapsFavoriteSets;

  /// Ключи оповещений о приближении.
  static bool isProximityKey(String key) => key.startsWith(SettingsKeys.proximityPrefix);
}
