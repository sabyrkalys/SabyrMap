import 'dart:io';

import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/repository/file_naming.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('baseFromName', () {
    test('lowercases and replaces spaces', () {
      expect(FileNaming.baseFromName('My Marker'), 'my_marker');
      expect(FileNaming.baseFromName('  Two   Spaces  '), 'two_spaces');
    });

    test('drops forbidden characters', () {
      expect(FileNaming.baseFromName('a/b:c'), 'abc');
      expect(FileNaming.baseFromName(r'x\y*z?"<>|'), 'xyz');
    });

    test('empty or fully stripped names become untitled', () {
      expect(FileNaming.baseFromName(''), 'untitled');
      expect(FileNaming.baseFromName('   '), 'untitled');
      expect(FileNaming.baseFromName('///'), 'untitled');
      expect(FileNaming.baseFromName('...'), 'untitled');
    });

    test('keeps Unicode and cuts to 64 characters', () {
      expect(FileNaming.baseFromName('Высота 312'), 'высота_312');
      expect(FileNaming.baseFromName('a' * 100), 'a' * 64);
      final emoji = FileNaming.baseFromName('🏔' * 70);
      expect(emoji.runes.length, 64);
    });
  });

  test('filename is <base>_<timestamp>.<ext>', () {
    final at = DateTime.fromMillisecondsSinceEpoch(1760000000123);
    expect(FileNaming.filename('Bunker', LandmarkType.waypoint, at: at), 'bunker_1760000000123.wpt');
    expect(FileNaming.filename('', LandmarkType.track, at: at), 'untitled_1760000000123.trk');
    expect(FileNaming.filename('Bunker', LandmarkType.waypoint), matches(RegExp(r'^bunker_\d+\.wpt$')));
  });

  group('resolveCollision', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('naming_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('returns the name itself when it is free', () async {
      expect(await FileNaming.resolveCollision(dir.path, 'bunker_1.wpt'), p.join(dir.path, 'bunker_1.wpt'));
    });

    test('adds _1, _2 before the extension when taken', () async {
      File(p.join(dir.path, 'bunker_1760000000123.wpt')).createSync();
      expect(
        await FileNaming.resolveCollision(dir.path, 'bunker_1760000000123.wpt'),
        p.join(dir.path, 'bunker_1760000000123_1.wpt'),
      );
      File(p.join(dir.path, 'bunker_1760000000123_1.wpt')).createSync();
      expect(
        await FileNaming.resolveCollision(dir.path, 'bunker_1760000000123.wpt'),
        p.join(dir.path, 'bunker_1760000000123_2.wpt'),
      );
    });
  });
}
