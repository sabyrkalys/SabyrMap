import 'file_map_metadata.dart';

/// Файловая карта для списка карт.
class FileMapDescriptor {
  const FileMapDescriptor({required this.metadata, required this.displayPath});

  final FileMapMetadata metadata;

  /// Путь для показа: относительно корня приложения.
  final String displayPath;
}
