class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8500',
  );

  /// Explicit base URL of our map tile server (Martin). Usually left empty:
  /// [mapServerBaseUrl] then derives it from [apiBaseUrl]. Override with
  /// --dart-define=MAP_SERVER_URL=http://host:3000 when the tiles live
  /// somewhere other than the API host on the default tile port.
  static const String _mapServerUrlOverride = String.fromEnvironment(
    'MAP_SERVER_URL',
    defaultValue: '',
  );

  /// Port Martin is reached on in development (exposed by
  /// docker-compose.override.yml). nginx fronts it on 443 in production, so
  /// production always sets MAP_SERVER_URL explicitly.
  static const int _devTilePort = 3000;

  /// Base URL for server tiles, e.g. `http://10.0.2.2:3000`. Defaults to the
  /// API host on [_devTilePort] so the same emulator / adb-reverse setup as
  /// the API just works.
  static String get mapServerBaseUrl {
    if (_mapServerUrlOverride.isNotEmpty) return _mapServerUrlOverride;
    return Uri.parse(apiBaseUrl).replace(port: _devTilePort).toString();
  }

  /// Google Map Tiles API key (a project with billing and the Map Tiles
  /// API enabled). Empty until one is issued: Google layers then report
  /// that the key is missing instead of loading.
  static const String googleMapsApiKey = '';

  /// Яндекс Tiles API key. Empty until one is issued: Яндекс layers then
  /// report that the key is missing instead of loading.
  static const String yandexMapsApiKey = '';

  /// Map providers hidden from the catalog for now (keys and terms still
  /// to be settled); their services stay in the code.
  static const Set<String> hiddenMapProviders = {'google', 'yandex'};

  static const String mapStyleUrl =
      'https://tiles.openfreemap.org/styles/liberty';
}
