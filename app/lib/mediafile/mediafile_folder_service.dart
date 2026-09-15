import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path_provider/path_provider.dart';

class MediaFileEntry {
  const MediaFileEntry({required this.path, required this.fileName, required this.sizeBytes});

  final String path;
  final String fileName;
  final int sizeBytes;
}

/// Lists, imports into, and deletes from one named subfolder under the
/// device's mediafile root. Uses the same external-storage-first / app-docs
/// fallback resolution as IconLibraryScanner (app/lib/icons/
/// icon_library_scanner.dart) -- duplicated rather than shared, since that
/// class is otherwise unrelated shipped code.
class MediaFileFolderService {
  MediaFileFolderService({required this.subfolder, FileSystem? fileSystem, this.baseDirectoryPath})
      : _fileSystem = fileSystem ?? const LocalFileSystem();

  final String subfolder;
  final String? baseDirectoryPath;
  final FileSystem _fileSystem;

  Future<Directory> _resolveDirectory() async {
    final fixed = baseDirectoryPath;
    if (fixed != null) return _fileSystem.directory(fixed);

    final external = await getExternalStorageDirectory();
    final base = external ?? await getApplicationDocumentsDirectory();
    return _fileSystem.directory('${base.path}/mediafile/$subfolder');
  }

  Future<List<MediaFileEntry>> list() async {
    final dir = await _resolveDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final entries = <MediaFileEntry>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      entries.add(MediaFileEntry(path: entity.path, fileName: entity.basename, sizeBytes: entity.lengthSync()));
    }
    entries.sort((a, b) => a.fileName.compareTo(b.fileName));
    return entries;
  }

  Future<void> importFile(String sourcePath) async {
    final dir = await _resolveDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final source = _fileSystem.file(sourcePath);
    final bytes = await source.readAsBytes();
    await dir.childFile(source.basename).writeAsBytes(bytes);
  }

  Future<void> delete(String fileName) async {
    final dir = await _resolveDirectory();
    final target = dir.childFile(fileName);
    if (await target.exists()) {
      await target.delete();
    }
  }
}
