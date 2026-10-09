import 'package:app/landmarks/explorer/display/display_registry.dart';
import 'package:app/landmarks/explorer/display/display_state.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DisplayRegistry registry;
  setUp(() => registry = DisplayRegistry());

  test('display and undisplay change the count', () {
    registry.display('/a');
    registry.display('/a');
    registry.displayAll(['/b', '/c']);
    expect(registry.count, 3);
    expect(registry.isDisplayed('/b'), isTrue);
    registry.undisplay('/b');
    registry.undisplayAll(['/c', '/zzz']);
    expect(registry.count, 1);
    registry.clear();
    expect(registry.state.isEmpty, isTrue);
  });

  test('listeners hear changes only', () {
    var notified = 0;
    registry.addListener(() => notified++);
    registry.display('/a');
    registry.display('/a');
    registry.undisplay('/zzz');
    expect(notified, 1);
  });

  test('prune drops paths that no longer exist', () {
    registry.displayAll(['/a', '/b', '/c']);
    registry.prune(['/a', '/c', '/d']);
    expect(registry.state.displayedPaths, {'/a', '/c'});
  });

  test('persist and restore per workspace', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    registry.displayAll(['/b', '/a']);
    await registry.persist('ws1', settings);
    expect(settings.getString('${SettingsKeys.displayedPrefix}ws1'), '["/a","/b"]');

    final other = DisplayRegistry();
    await other.restore('ws1', settings);
    expect(other.state.displayedPaths, {'/a', '/b'});
    await other.restore('ws2', settings);
    expect(other.state.isEmpty, isTrue);

    await settings.setString('${SettingsKeys.displayedPrefix}bad', 'not json');
    await other.restore('bad', settings);
    expect(other.state.isEmpty, isTrue);
  });

  test('DisplayState operations', () {
    const empty = DisplayState();
    final one = empty.withDisplayed('/a');
    expect(one.count, 1);
    expect(one.toggle('/a').isEmpty, isTrue);
    expect(one.withUndisplayed('/zzz'), one);
  });
}
