import 'package:app/mediafile/mediafile_folder_service.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaFileFolderService', () {
    test('creates the folder when missing and returns an empty list', () async {
      final fs = MemoryFileSystem();
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      final result = await service.list();

      expect(result, isEmpty);
      expect(fs.directory('/base/mediafile/custom-types').existsSync(), isTrue);
    });

    test('lists files with name and size, sorted by filename', () async {
      final fs = MemoryFileSystem();
      final dir = fs.directory('/base/mediafile/custom-types')..createSync(recursive: true);
      dir.childFile('zebra.png').writeAsBytesSync([1, 2, 3]);
      dir.childFile('arrow.svg').writeAsBytesSync([1, 2]);
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      final result = await service.list();

      expect(result.map((e) => e.fileName), ['arrow.svg', 'zebra.png']);
      expect(result.firstWhere((e) => e.fileName == 'arrow.svg').sizeBytes, 2);
      expect(result.firstWhere((e) => e.fileName == 'zebra.png').sizeBytes, 3);
    });

    test('importFile copies bytes from the source path into the folder under its basename', () async {
      final fs = MemoryFileSystem();
      fs.directory('/downloads').createSync(recursive: true);
      fs.file('/downloads/marker.svg').writeAsBytesSync([9, 9, 9]);
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      await service.importFile('/downloads/marker.svg');

      final imported = fs.file('/base/mediafile/custom-types/marker.svg');
      expect(imported.existsSync(), isTrue);
      expect(imported.readAsBytesSync(), [9, 9, 9]);
    });

    test('importFile overwrites an existing file with the same name', () async {
      final fs = MemoryFileSystem();
      fs.directory('/downloads').createSync(recursive: true);
      fs.file('/downloads/marker.svg').writeAsBytesSync([9, 9, 9]);
      final dir = fs.directory('/base/mediafile/custom-types')..createSync(recursive: true);
      dir.childFile('marker.svg').writeAsBytesSync([1]);
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      await service.importFile('/downloads/marker.svg');

      expect(fs.file('/base/mediafile/custom-types/marker.svg').readAsBytesSync(), [9, 9, 9]);
    });

    test('delete removes a file', () async {
      final fs = MemoryFileSystem();
      final dir = fs.directory('/base/mediafile/custom-types')..createSync(recursive: true);
      dir.childFile('marker.svg').createSync();
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      await service.delete('marker.svg');

      expect(fs.file('/base/mediafile/custom-types/marker.svg').existsSync(), isFalse);
    });

    test('delete tolerates a file that does not exist', () async {
      final fs = MemoryFileSystem();
      final service = MediaFileFolderService(
        subfolder: 'custom-types',
        fileSystem: fs,
        baseDirectoryPath: '/base/mediafile/custom-types',
      );

      await service.delete('does-not-exist.svg'); // must not throw
    });
  });
}
