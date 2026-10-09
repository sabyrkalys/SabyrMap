import 'package:app/landmarks/models/landmark_type.dart';

/// Файл метки в буфере проводника.
class ClipboardEntry {
  const ClipboardEntry({required this.sourcePath, required this.type, required this.originalName});

  final String sourcePath;
  final LandmarkType type;

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
