import 'package:app/app_settings/app_settings_controller.dart';
import 'package:app/app_settings/app_settings_model.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettings settings;
  late AppSettingsController c;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    c = AppSettingsController(settings);
    await c.load();
  });

  test('defaults', () {
    expect(c.model, const AppSettingsModel());
    expect(c.model.locale, 'ru');
    expect(c.model.uiScale, 1.0);
  });

  test('every setter changes the model and is saved', () async {
    await c.setLocale('en');
    await c.setDarkMode(true);
    await c.setMapRotationEnabled(false);
    await c.setPerspectiveEnabled(true);
    await c.setLockMapEnabled(true);
    await c.setUiScale(1.2);
    await c.setPrimaryCoordsFormat('sk42');
    await c.setSecondaryCoordsFormat('wgs84');
    await c.setDisplayGrid(true);
    await c.setDisplayAltGrid(true);
    final expected = const AppSettingsModel(
      locale: 'en',
      darkMode: true,
      mapRotationEnabled: false,
      perspectiveEnabled: true,
      lockMapEnabled: true,
      uiScale: 1.2,
      primaryCoordsFormat: 'sk42',
      secondaryCoordsFormat: 'wgs84',
      displayGrid: true,
      displayAltGrid: true,
    );
    expect(c.model, expected);
    final again = AppSettingsController(settings);
    await again.load();
    expect(again.model, expected);
    await c.setSecondaryCoordsFormat(null);
    expect(c.model.secondaryCoordsFormat, isNull);
  });

  test('validation rejects bad values', () async {
    expect(() => c.setUiScale(0.5), throwsArgumentError);
    expect(() => c.setUiScale(1.6), throwsArgumentError);
    expect(() => c.setLocale('xx'), throwsArgumentError);
    expect(() => c.setPrimaryCoordsFormat('utm'), throwsArgumentError);
    expect(() => c.setSecondaryCoordsFormat('utm'), throwsArgumentError);
    expect(c.model, const AppSettingsModel());
  });

  test('bad stored values load as defaults', () async {
    await settings.setString('app.ui_scale', '9');
    await settings.setString('app.locale', 'zz');
    await c.load();
    expect(c.model.uiScale, 1.0);
    expect(c.model.locale, 'ru');
  });

  test('reset returns defaults and leaves other settings alone', () async {
    await settings.setString('maps.current_source', 'topo');
    await c.setDarkMode(true);
    await c.setUiScale(0.9);
    await c.reset();
    expect(c.model, const AppSettingsModel());
    expect(settings.getString('app.dark_mode'), isNull);
    expect(settings.getString('maps.current_source'), 'topo');
  });
}
