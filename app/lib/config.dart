class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8500',
  );

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
