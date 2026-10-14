import 'dart:io';

import 'package:app/exceptions/storage_exception.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const root = '/data/sabyrmap/files';
  final paths = StoragePaths.forRoot(root);

  List<String> allPaths(StoragePaths s) => [
    s.landmarks,
    s.datastore,
    s.datastoreMaps,
    s.datastoreDem,
    s.icons,
    s.logs,
    s.maps,
    s.pictures,
    s.importDefault,
    s.recordedTracks,
  ];

  test('every path is non-empty, POSIX-style and lives under appRoot', () {
    expect(paths.appRoot, root);
    for (final path in allPaths(paths)) {
      expect(path, isNotEmpty);
      expect(path, startsWith('$root/'));
      expect(path, isNot(contains(r'\')));
    }
    expect(paths.datastoreMaps, '$root/datastore/maps');
    expect(paths.importDefault, '$root/landmarks/Несортированные метки');
    expect(paths.recordedTracks, '$root/landmarks/Записанные треки');
  });

  test('no path names a third-party product', () {
    const forbidden = ['alpinequest', 'psyberia'];
    for (final path in [paths.appRoot, ...allPaths(paths)]) {
      for (final word in forbidden) {
        expect(path.toLowerCase(), isNot(contains(word)));
      }
    }
    final offenders = [
      for (final file in [
        ...Directory('lib/storage').listSync(recursive: true),
        ...Directory('lib/landmarks').listSync(recursive: true),
        ...Directory('lib/exceptions').listSync(recursive: true),
      ].whereType<File>())
        if (forbidden.any(file.readAsStringSync().toLowerCase().contains)) file.path,
    ];
    expect(offenders, isEmpty);
  });

  group('resolveInLandmarks', () {
    test('puts a file name inside landmarks', () {
      expect(paths.resolveInLandmarks('bunker_1.wpt'), '$root/landmarks/bunker_1.wpt');
    });

    test('keeps subfolders inside landmarks', () {
      expect(paths.resolveInLandmarks('Поход/a.trk'), '$root/landmarks/Поход/a.trk');
    });

    test('never escapes landmarks', () {
      expect(paths.resolveInLandmarks('../../etc/passwd'), '$root/landmarks/passwd');
      expect(paths.resolveInLandmarks('/abs/x.wpt'), '$root/landmarks/x.wpt');
      expect(paths.resolveInLandmarks('..'), '$root/landmarks');
    });
  });

  group('resolveWith', () {
    test('takes the first directory that is available', () async {
      final resolved = await StoragePaths.resolveWith([
        () async => throw UnsupportedError('no external storage'),
        () async => null,
        () async => Directory('/docs/root'),
        () async => Directory('/support/root'),
      ]);
      expect(resolved.appRoot, '/docs/root/mediafile');
    });

    test('throws StorageException when nothing is available', () async {
      expect(
        () => StoragePaths.resolveWith([() async => null, () async => throw UnsupportedError('x')]),
        throwsA(isA<StorageException>()),
      );
    });
  });
}
