import 'package:app/icons/icon_library_scanner.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iconFileFormatForPath', () {
    test('recognizes svg', () {
      expect(iconFileFormatForPath('a/volcano.svg'), IconFileFormat.svg);
      expect(iconFileFormatForPath('a/volcano.SVG'), IconFileFormat.svg);
    });

    test('recognizes png and jpg/jpeg as raster', () {
      expect(iconFileFormatForPath('a/b.png'), IconFileFormat.raster);
      expect(iconFileFormatForPath('a/b.JPG'), IconFileFormat.raster);
      expect(iconFileFormatForPath('a/b.jpeg'), IconFileFormat.raster);
    });

    test('returns null for unsupported extensions', () {
      expect(iconFileFormatForPath('a/b.gif'), isNull);
      expect(iconFileFormatForPath('a/b.txt'), isNull);
      expect(iconFileFormatForPath('a/b'), isNull);
    });
  });

  group('IconLibraryScanner', () {
    test('creates the folder when missing and returns an empty list', () async {
      final fs = MemoryFileSystem();
      final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base/mediafile/iconTypes');

      final result = await scanner.scan();

      expect(result, isEmpty);
      expect(fs.directory('/base/mediafile/iconTypes').existsSync(), isTrue);
    });

    test('lists supported files sorted by filename, ignoring unsupported ones', () async {
      final fs = MemoryFileSystem();
      final dir = fs.directory('/base/mediafile/iconTypes')..createSync(recursive: true);
      dir.childFile('zebra.png').createSync();
      dir.childFile('arrow.svg').createSync();
      dir.childFile('notes.txt').createSync();
      dir.childFile('camp.jpeg').createSync();
      final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base/mediafile/iconTypes');

      final result = await scanner.scan();

      expect(result.map((f) => f.fileName), ['arrow.svg', 'camp.jpeg', 'zebra.png']);
      expect(result.map((f) => f.displayName), ['arrow', 'camp', 'zebra']);
      expect(result[0].format, IconFileFormat.svg);
      expect(result[1].format, IconFileFormat.raster);
    });
  });
}
