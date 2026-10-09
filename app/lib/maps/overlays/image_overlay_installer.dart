import 'dart:convert';
import 'dart:io';

import 'package:app/landmarks/repository/file_naming.dart';
import 'package:app/maps/file_maps/file_map_metadata.dart';
import 'package:app/maps/file_maps/file_map_scanner.dart';
import 'package:app/storage/storage_paths.dart';
import 'package:app/storage/storage_service.dart';
import 'package:path/path.dart' as p;

import 'kml_overlay_descriptor.dart';

/// Ставит картинку-наложение в `<корень>/maps` рядом с файлом `.bounds`,
/// который читает [FileMapScanner].
class ImageOverlayInstaller {
  ImageOverlayInstaller(this._paths, this._storage);

  final StoragePaths _paths;
  final StorageService _storage;

  Future<FileMapMetadata> install(KmlOverlayDescriptor desc) async {
    final ext = p.extension(desc.imagePath).toLowerCase();
    await Directory(_paths.maps).create(recursive: true);
    final target = await FileNaming.resolveCollision(_paths.maps, '${FileNaming.baseFromName(desc.name)}$ext');
    final bytes = await _storage.readBytes(desc.imagePath);
    await _storage.atomicWriteBytes(target, bytes);
    await _storage.atomicWriteBytes(
      '$target${FileMapScanner.boundsExtension}',
      utf8.encode(jsonEncode({...desc.bounds.toJson(), 'rotation': desc.rotation, 'name': desc.name})),
    );
    final stat = await File(target).stat();
    return FileMapMetadata(
      path: target,
      displayName: desc.name,
      sourceFormatId: 'image',
      bounds: desc.bounds,
      fileSizeBytes: stat.size,
      lastModified: stat.modified.millisecondsSinceEpoch,
    );
  }
}
