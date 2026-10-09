import 'map_bounds.dart';

/// Метаданные файловой карты (без тайлов).
class FileMapMetadata {
  const FileMapMetadata({
    required this.path,
    required this.displayName,
    required this.sourceFormatId,
    this.bounds,
    this.minZoom,
    this.maxZoom,
    this.tileSize,
    this.fileSizeBytes,
    this.lastModified,
  });

  final String path;
  final String displayName;

  /// id в [MapSourceRegistry].
  final String sourceFormatId;

  /// Decision: null — границы неизвестны (изображение не откалибровано или
  /// формат, границы которого здесь не читаются, без файла `.bounds`).
  final MapBounds? bounds;
  final int? minZoom;
  final int? maxZoom;
  final int? tileSize;
  final int? fileSizeBytes;

  /// Unix ms.
  final int? lastModified;
}
