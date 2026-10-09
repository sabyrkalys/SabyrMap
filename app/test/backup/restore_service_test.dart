import 'dart:convert';
import 'dart:io';

import 'package:app/backup/backup_data_type.dart';
import 'package:app/backup/backup_request.dart';
import 'package:app/backup/restore_request.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'backup_fixture.dart';

void main() {
  late BackupFixture source;
  late String archive;
  setUp(() async {
    source = await BackupFixture.create(prefs: {'app.locale': 'en', 'app.ui_scale': '1.2'});
    source.fill();
    archive = source.target();
    final result = await source.backup().backup(
      BackupRequest(targetPath: archive, types: BackupDataType.values.toSet()),
    );
    expect(result.success, isTrue);
  });
  tearDown(() => source.dispose());

  Future<BackupFixture> emptyApp() async {
    final f = await BackupFixture.create(name: 'restored');
    addTearDown(f.dispose);
    return f;
  }

  test('round-trip into an empty app: every file in place, settings back', () async {
    final target = await emptyApp();
    final result = await target.restore().restore(
      RestoreRequest(sourcePath: archive, types: BackupDataType.values.toSet()),
    );
    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.needsRestart, isTrue);
    for (final (folder, name) in [
      (target.paths.landmarks, 'a.wpt'),
      (p.join(target.paths.landmarks, 'trips'), 'b.trk'),
      (target.paths.icons, 'tent.png'),
      (target.paths.maps, 'topo.mbtiles'),
      (target.paths.datastoreMaps, 'online.aqx'),
      (target.paths.datastoreDem, 'N50E030.hgt'),
    ]) {
      expect(File(p.join(folder, name)).existsSync(), isTrue, reason: name);
    }
    expect(File(p.join(target.paths.landmarks, 'a.wpt')).readAsStringSync(), 'wpt-a');
    expect(target.settings.getString('app.locale'), 'en');
    expect(result.restoredFiles, 6 + 4);
  });

  test('only chosen types are restored; no settings, no restart', () async {
    final target = await emptyApp();
    final result = await target.restore().restore(RestoreRequest(sourcePath: archive, types: {BackupDataType.maps}));
    expect(result.restoredFiles, 1);
    expect(result.needsRestart, isFalse);
    expect(File(p.join(target.paths.icons, 'tent.png')).existsSync(), isFalse);
  });

  test('without overwrite existing files are kept (warning); landmarks come back as _restored', () async {
    final target = await emptyApp();
    File(p.join(target.paths.maps, 'topo.mbtiles')).writeAsStringSync('mine');
    File(p.join(target.paths.landmarks, 'a.wpt')).writeAsStringSync('my-a');
    final result = await target.restore().restore(
      RestoreRequest(sourcePath: archive, types: {BackupDataType.maps, BackupDataType.landmarks}),
    );
    expect(result.success, isTrue);
    expect(File(p.join(target.paths.maps, 'topo.mbtiles')).readAsStringSync(), 'mine');
    expect(File(p.join(target.paths.landmarks, 'a.wpt')).readAsStringSync(), 'my-a');
    expect(File(p.join(target.paths.landmarks, 'a_restored.wpt')).readAsStringSync(), 'wpt-a');
    expect(result.warnings, hasLength(2));
  });

  test('with overwrite the chosen types are replaced, others kept', () async {
    final target = await emptyApp();
    File(p.join(target.paths.maps, 'topo.mbtiles')).writeAsStringSync('mine');
    File(p.join(target.paths.maps, 'extra.mbtiles')).writeAsStringSync('extra');
    File(p.join(target.paths.icons, 'own.png')).writeAsStringSync('own');
    final result = await target.restore().restore(
      RestoreRequest(sourcePath: archive, types: {BackupDataType.maps}, overwriteExisting: true),
    );
    expect(result.success, isTrue);
    expect(File(p.join(target.paths.maps, 'topo.mbtiles')).readAsStringSync(), 'map-data');
    expect(File(p.join(target.paths.maps, 'extra.mbtiles')).existsSync(), isFalse);
    expect(File(p.join(target.paths.icons, 'own.png')).existsSync(), isTrue);
  });

  test('a bad or newer manifest, or not a backup, fails', () async {
    final target = await emptyApp();
    Future<String> zip(String name, Map<String, String> files) async {
      final a = Archive();
      for (final e in files.entries) {
        a.addFile(ArchiveFile.bytes(e.key, utf8.encode(e.value)));
      }
      final path = p.join(source.root.path, name);
      File(path).writeAsBytesSync(ZipEncoder().encodeBytes(a));
      return path;
    }

    for (final path in [
      await zip('newer.zip', {'manifest.json': '{"version":2,"createdAt":1,"appVersion":"9","entries":[]}'}),
      await zip('broken.zip', {'manifest.json': '{nope'}),
      await zip('none.zip', {'maps/x.mbtiles': 'x'}),
    ]) {
      final result = await target.restore().restore(RestoreRequest(sourcePath: path, types: {BackupDataType.maps}));
      expect(result.success, isFalse, reason: path);
      expect(result.errorMessage, isNotNull);
    }
    final notZip = File(p.join(source.root.path, 'x.zip'))..writeAsStringSync('hello');
    expect((await target.restore().restore(RestoreRequest(sourcePath: notZip.path, types: const {}))).success, isFalse);
    expect(
      (await target.restore().restore(RestoreRequest(sourcePath: '/no/file.zip', types: const {}))).success,
      isFalse,
    );
  });

  test('unsafe paths in the archive are skipped', () async {
    final target = await emptyApp();
    final a = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'manifest.json',
          utf8.encode('{"version":1,"createdAt":1,"appVersion":"1","entries":[{"type":"maps","path":"maps/","bytes":1,"files":1}]}'),
        ),
      )
      ..addFile(ArchiveFile.bytes('maps/../../evil.txt', [1]));
    final path = p.join(source.root.path, 'evil.zip');
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(a));
    final result = await target.restore().restore(RestoreRequest(sourcePath: path, types: {BackupDataType.maps}));
    expect(result.restoredFiles, 0);
    expect(result.warnings.single, contains('Unsafe'));
  });
}
