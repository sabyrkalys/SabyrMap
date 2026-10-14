import 'dart:io';

import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  late String files;
  late StoragePaths paths;
  late StorageService service;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mediafile_migration');
    files = p.join(tmp.path, 'files');
    paths = StoragePaths.forRoot(p.join(files, 'mediafile'));
    service = StorageService(paths);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('migrateIntoMediafile', () {
    test('moves the folders from files/ into files/mediafile/', () async {
      File(p.join(files, 'landmarks', 'Поход', 'a.wpt')).createSync(recursive: true);
      File(p.join(files, 'datastore', 'dem', 'N50E030.hgt')).createSync(recursive: true);

      final moved = await service.migrateIntoMediafile();

      expect(moved, {
        p.join(files, 'landmarks'): paths.landmarks,
        p.join(files, 'datastore'): paths.datastore,
      });
      expect(Directory(p.join(files, 'landmarks')).existsSync(), isFalse);
      expect(File(p.join(paths.landmarks, 'Поход', 'a.wpt')).existsSync(), isTrue);
      expect(File(p.join(paths.datastoreDem, 'N50E030.hgt')).existsSync(), isTrue);
      expect(await service.migrateIntoMediafile(), isEmpty);
    });

    test('merges into a folder mediafile already has; taken names get _1', () async {
      File(p.join(files, 'maps', 'only-old.mbtiles')).createSync(recursive: true);
      File(p.join(files, 'maps', 'a.mbtiles')).writeAsBytesSync([1]);
      File(p.join(files, 'maps', 'region', 'r.mbtiles')).createSync(recursive: true);
      File(p.join(paths.maps, 'a.mbtiles')).createSync(recursive: true);
      File(p.join(paths.maps, 'a.mbtiles')).writeAsBytesSync([2]);
      File(p.join(paths.maps, 'region', 'style.json')).createSync(recursive: true);

      await service.migrateIntoMediafile();

      expect(Directory(p.join(files, 'maps')).existsSync(), isFalse);
      expect(File(p.join(paths.maps, 'a.mbtiles')).readAsBytesSync(), [2]);
      expect(File(p.join(paths.maps, 'a_1.mbtiles')).readAsBytesSync(), [1]);
      expect(File(p.join(paths.maps, 'only-old.mbtiles')).existsSync(), isTrue);
      expect(File(p.join(paths.maps, 'region', 'r.mbtiles')).existsSync(), isTrue);
      expect(File(p.join(paths.maps, 'region', 'style.json')).existsSync(), isTrue);
    });

    test('leaves files/ alone when the root is not mediafile', () async {
      File(p.join(files, 'landmarks', 'a.wpt')).createSync(recursive: true);
      expect(await StorageService(StoragePaths.forRoot(files)).migrateIntoMediafile(), isEmpty);
      expect(File(p.join(files, 'landmarks', 'a.wpt')).existsSync(), isTrue);
    });
  });

  group('AppSettings.movePaths', () {
    test('rewrites moved paths in values, lists and keys, whole segments only', () async {
      SharedPreferences.setMockInitialValues({
        'folder': '/f/landmarks/Поход',
        'shown': '["/f/landmarks/a.wpt","/f/maps/b.mbtiles"]',
        'list': ['/f/landmarks', '/f/landmarksX/c'],
        'view./f/landmarks/Поход': 'grid',
        'other': '/f/mediafile/maps/x.mbtiles',
        'flag': true,
      });
      final prefs = await SharedPreferences.getInstance();

      await AppSettings(prefs).movePaths({
        '/f/landmarks': '/f/mediafile/landmarks',
        '/f/maps': '/f/mediafile/maps',
      });

      expect(prefs.getString('folder'), '/f/mediafile/landmarks/Поход');
      expect(prefs.getString('shown'), '["/f/mediafile/landmarks/a.wpt","/f/mediafile/maps/b.mbtiles"]');
      expect(prefs.getStringList('list'), ['/f/mediafile/landmarks', '/f/landmarksX/c']);
      expect(prefs.getString('view./f/mediafile/landmarks/Поход'), 'grid');
      expect(prefs.containsKey('view./f/landmarks/Поход'), isFalse);
      expect(prefs.getString('other'), '/f/mediafile/maps/x.mbtiles');
      expect(prefs.getBool('flag'), isTrue);
    });
  });
}
