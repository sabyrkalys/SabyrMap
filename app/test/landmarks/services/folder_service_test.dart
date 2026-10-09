import 'dart:io';

import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture.dart';

void main() {
  late ServicesFixture f;
  setUp(() async => f = await ServicesFixture.create());
  tearDown(() => f.dispose());

  test('without a setting the default folder is «Несортированные метки»', () async {
    expect(await f.services.folders.getDefaultFolder(), f.paths.importDefault);
  });

  test('setDefaultFolder is remembered and does not create the folder', () async {
    final dir = p.join(f.paths.landmarks, 'trip');
    await f.services.folders.setDefaultFolder(dir);
    expect(Directory(dir).existsSync(), isFalse);
    await f.services.folders.ensureFolder(dir);
    expect(await f.services.folders.getDefaultFolder(), dir);
  });

  test('a deleted default folder falls back and the setting is reset', () async {
    final dir = p.join(f.paths.landmarks, 'gone');
    await f.services.folders.ensureFolder(dir);
    await f.services.folders.setDefaultFolder(dir);
    Directory(dir).deleteSync();
    expect(await f.services.folders.getDefaultFolder(), f.paths.importDefault);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsKeys.defaultFolder), isNull);
  });

  test('current folder is stored, cleared and forgotten when deleted', () async {
    expect(await f.services.folders.getCurrentFolder(), isNull);
    await f.services.folders.setCurrentFolder(f.paths.recordedTracks);
    expect(await f.services.folders.getCurrentFolder(), f.paths.recordedTracks);
    await f.services.folders.setCurrentFolder(null);
    expect(await f.services.folders.getCurrentFolder(), isNull);

    final dir = p.join(f.paths.landmarks, 'tmp');
    await f.services.folders.ensureFolder(dir);
    await f.services.folders.setCurrentFolder(dir);
    Directory(dir).deleteSync();
    expect(await f.services.folders.getCurrentFolder(), isNull);
  });

  test('listSubfolders returns folders only, sorted', () async {
    File(p.join(f.paths.landmarks, 'a.wpt')).writeAsBytesSync([0]);
    Link(p.join(f.paths.landmarks, 'link')).createSync(f.paths.maps);
    final subfolders = await f.services.folders.listSubfolders(f.paths.landmarks);
    expect(subfolders, [f.paths.recordedTracks, f.paths.importDefault]);
    expect(await f.services.folders.listSubfolders(p.join(f.paths.landmarks, 'none')), isEmpty);
  });

  test('ensureFolder is idempotent and creates parents', () async {
    final dir = p.join(f.paths.landmarks, 'a', 'b', 'c');
    await f.services.folders.ensureFolder(dir);
    await f.services.folders.ensureFolder(dir);
    expect(Directory(dir).existsSync(), isTrue);
  });

  test('an empty folder path is rejected', () async {
    expect(() => f.services.folders.setDefaultFolder('  '), throwsArgumentError);
  });
}
