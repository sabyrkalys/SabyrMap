import 'package:app/landmarks/models/landmark_type.dart';

/// Файл метки или папка в буфере проводника.
class ClipboardEntry {
  const ClipboardEntry({required this.sourcePath, required this.type, required this.originalName});

  /// Папка в буфере.
  const ClipboardEntry.folder({required this.sourcePath, required this.originalName}) : type = null;

  final String sourcePath;

  /// Тип файла метки; null — папка.
  final LandmarkType? type;

  bool get isFolder => type == null;

  /// Имя объекта на момент копирования.
  final String originalName;

  @override
  bool operator ==(Object other) =>
      other is ClipboardEntry &&
      other.sourcePath == sourcePath &&
      other.type == type &&
      other.originalName == originalName;

  @override
  int get hashCode => Object.hash(sourcePath, type, originalName);
}
