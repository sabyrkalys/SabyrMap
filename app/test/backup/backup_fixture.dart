import 'dart:io';

import 'package:app/backup/backup_service.dart';
import 'package:app/backup/restore_service.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Корень приложения с файлами всех типов и настройками.
class BackupFixture {
  BackupFixture._(this.root, this.paths, this.storage, this.settings);

  final Directory root;
  final StoragePaths paths;
  final StorageService storage;
  final AppSettings settings;

  static Future<BackupFixture> create({String name = 'app', Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final root = Directory.systemTemp.createTempSync('backup_');
    final paths = StoragePaths.forRoot(p.join(root.path, name));
    final storage = StorageService(paths);
    await storage.ensureBaseFolders();
    return BackupFixture._(root, paths, storage, AppSettings(await SharedPreferences.getInstance()));
  }

  void fill() {
    _write(p.join(paths.landmarks, 'a.wpt'), 'wpt-a');
    _write(p.join(paths.landmarks, 'trips', 'b.trk'), 'trk-b');
    _write(p.join(paths.icons, 'tent.png'), 'png');
    _write(p.join(paths.maps, 'topo.mbtiles'), 'map-data');
    _write(p.join(paths.datastoreMaps, 'online.aqx'), '<aqx/>');
    _write(p.join(paths.datastoreDem, 'N50E030.hgt'), 'hgt');
  }

  BackupService backup({int? maxBytes}) => BackupService(
    paths,
    storage,
    settings,
    appVersion: '1.0.0',
    maxArchiveBytes: maxBytes ?? BackupService.defaultMaxArchiveBytes,
    clock: () => DateTime.fromMillisecondsSinceEpoch(1760000000000),
  );

  RestoreService restore() => RestoreService(paths, storage, settings);

  String target([String name = 'my.saby-backup.zip']) => p.join(root.path, name);

  static void _write(String path, String text) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  void dispose() => root.deleteSync(recursive: true);
}
