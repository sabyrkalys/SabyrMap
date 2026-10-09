import 'dart:convert';
import 'dart:io';

import 'package:app/backup/backup_data_type.dart';
import 'package:app/backup/backup_manifest.dart';
import 'package:app/backup/backup_request.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'backup_fixture.dart';

void main() {
  late BackupFixture f;
  setUp(() async {
    f = await BackupFixture.create(
      prefs: {'app.locale': 'en', 'workspace.list': '[]', 'maps.favorite_sets': '[]', 'navigation.proximity.default': '[]'},
    );
    f.fill();
  });
  tearDown(() => f.dispose());

  Archive read(String path) => ZipDecoder().decodeBytes(File(path).readAsBytesSync());

  test('a full backup: ZIP with every type and a manifest', () async {
    final result = await f.backup().backup(
      BackupRequest(targetPath: f.target(), types: BackupDataType.values.toSet()),
    );
    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.filePath, f.target());
    final archive = read(f.target());
    final names = archive.files.map((e) => e.name).toSet();
    expect(
      names,
      containsAll([
        'manifest.json',
        'landmarks/a.wpt',
        'landmarks/trips/b.trk',
        'icons/tent.png',
        'maps/topo.mbtiles',
        'datastore/maps/online.aqx',
        'datastore/dem/N50E030.hgt',
        'settings.json',
        'workspaces.json',
        'favorite_sets.json',
        'proximity_alerts.json',
      ]),
    );
    final manifest = BackupManifest.decode(utf8.decode(archive.findFile('manifest.json')!.content));
    expect(manifest.version, 1);
    expect(manifest.appVersion, '1.0.0');
    expect(manifest.entries.map((e) => e.type).toSet(), BackupDataType.values.toSet());
    final landmarks = manifest.entries.firstWhere((e) => e.type == BackupDataType.landmarks);
    expect((landmarks.fileCount, landmarks.byteCount), (2, 10));
    final settings = jsonDecode(utf8.decode(archive.findFile('settings.json')!.content)) as Map<String, dynamic>;
    expect(settings['app.locale'], 'en');
    final ws = jsonDecode(utf8.decode(archive.findFile('workspaces.json')!.content)) as Map<String, dynamic>;
    expect(ws.keys, ['workspace.list']);
    expect(File('${f.target()}.tmp').existsSync(), isFalse);
  });

  test('only chosen landmark folders; sources untouched', () async {
    final before = File(p.join(f.paths.landmarks, 'a.wpt')).readAsStringSync();
    final result = await f.backup().backup(
      BackupRequest(
        targetPath: f.target(),
        types: {BackupDataType.landmarks},
        includeFullLandmarks: false,
        includedFolders: [p.join(f.paths.landmarks, 'trips'), '/elsewhere'],
      ),
    );
    expect(result.totalFiles, 1);
    expect(read(f.target()).files.map((e) => e.name), containsAll(['landmarks/trips/b.trk', 'manifest.json']));
    expect(File(p.join(f.paths.landmarks, 'a.wpt')).readAsStringSync(), before);
  });

  test('the size estimate matches the content', () async {
    final request = BackupRequest(
      targetPath: f.target(),
      types: {BackupDataType.landmarks, BackupDataType.maps, BackupDataType.dem},
    );
    expect(await f.backup().estimateSize(request), 10 + 8 + 3);
    final result = await f.backup().backup(request);
    expect(result.totalBytes, 21);
    expect(result.totalFiles, 4);
  });

  test('over the archive limit fails with a warning and writes nothing', () async {
    final result = await f.backup(maxBytes: 10).backup(
      BackupRequest(targetPath: f.target(), types: {BackupDataType.maps, BackupDataType.landmarks}),
    );
    expect(result.success, isFalse);
    expect(result.warnings.single, contains('limit'));
    expect(File(f.target()).existsSync(), isFalse);
  });

  test('a target folder that does not exist fails', () async {
    final result = await f.backup().backup(
      BackupRequest(targetPath: p.join(f.root.path, 'no', 'such', 'x.zip'), types: {BackupDataType.maps}),
    );
    expect(result.success, isFalse);
    expect(result.errorMessage, contains('Cannot write'));
  });

  test('nothing selected fails', () async {
    final result = await f.backup().backup(BackupRequest(targetPath: f.target(), types: const {}));
    expect(result.success, isFalse);
  });
}
