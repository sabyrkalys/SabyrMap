class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8500',
  );

  static const String mapStyleUrl =
      'https://tiles.openfreemap.org/styles/liberty';

  // TEMPORARY: skips the login screen by auto-authenticating a dev account so
  // the main app flow can be tested without typing credentials. Off by
  // default (and thus in tests/CI); enable with --dart-define=DEV_AUTO_LOGIN=true.
  static const bool devAutoLoginEnabled = bool.fromEnvironment('DEV_AUTO_LOGIN');
}
