import 'dart:io';

import 'package:app/backup/size_estimator.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('size_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('estimateLandmarks counts landmark files only, with subfolders', () async {
    File(p.join(root.path, 'a.wpt')).writeAsBytesSync(List.filled(100, 1));
    Directory(p.join(root.path, 'sub')).createSync();
    File(p.join(root.path, 'sub', 'b.trk')).writeAsBytesSync(List.filled(250, 1));
    File(p.join(root.path, 'notes.txt')).writeAsBytesSync(List.filled(999, 1));
    Link(p.join(root.path, 'link.wpt')).createSync(p.join(root.path, 'a.wpt'));
    expect(await SizeEstimator.estimateLandmarks(root.path), 350);
    expect(await SizeEstimator.estimateFolder(root.path), 1349);
    expect(await SizeEstimator.countFiles(root.path), 3);
    expect(await SizeEstimator.estimateFolder(p.join(root.path, 'none')), 0);
  });

  test('estimateSettings is the size of settings.json', () async {
    SharedPreferences.setMockInitialValues({'app.locale': 'ru'});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final size = await SizeEstimator.estimateSettings(settings);
    expect(size, SizeEstimator.encodeSettings({'app.locale': 'ru'}).length);
  });
}
