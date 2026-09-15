import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path_provider/path_provider.dart';

import '../mediafile/mediafile_subfolders.dart';

enum IconFileFormat { svg, raster }

class IconFile {
  const IconFile({required this.path, required this.fileName, required this.displayName, required this.format});

  final String path;
  final String fileName;
  final String displayName;
  final IconFileFormat format;
}

/// Pure classification of a file path's extension. Extracted as a top-level
/// function so it's unit-testable without touching any filesystem.
IconFileFormat? iconFileFormatForPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.svg')) return IconFileFormat.svg;
  if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return IconFileFormat.raster;
  return null;
}

/// Scans the device folder the user drops icon files into. Takes an
/// injectable [FileSystem] (defaulting to the real one) and an optional
/// fixed [baseDirectoryPath] so tests can point it at a [MemoryFileSystem]
/// path without touching real device storage or platform channels.
class IconLibraryScanner {
  IconLibraryScanner({FileSystem? fileSystem, this.baseDirectoryPath})
      : _fileSystem = fileSystem ?? const LocalFileSystem();

  final FileSystem _fileSystem;
  final String? baseDirectoryPath;

  static const _folderSuffix = 'mediafile/$kCustomTypesSubfolder';

  Future<Directory> resolveBaseDirectory() async {
    final fixed = baseDirectoryPath;
    if (fixed != null) return _fileSystem.directory(fixed);

    final external = await getExternalStorageDirectory();
    final base = external ?? await getApplicationDocumentsDirectory();
    return _fileSystem.directory('${base.path}/$_folderSuffix');
  }

  Future<List<IconFile>> scan() async {
    final dir = await resolveBaseDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final entries = <IconFile>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final format = iconFileFormatForPath(entity.path);
      if (format == null) continue;
      final fileName = entity.basename;
      final dot = fileName.lastIndexOf('.');
      final displayName = dot > 0 ? fileName.substring(0, dot) : fileName;
      entries.add(IconFile(path: entity.path, fileName: fileName, displayName: displayName, format: format));
    }
    entries.sort((a, b) => a.fileName.compareTo(b.fileName));
    return entries;
  }
}
