import 'backup_data_type.dart';

/// Запись манифеста: что и сколько лежит в архиве по одному типу.
class BackupManifestEntry {
  const BackupManifestEntry({
    required this.type,
    required this.relativePath,
    required this.byteCount,
    required this.fileCount,
  });

  final BackupDataType type;

  /// Путь в архиве.
  final String relativePath;
  final int byteCount;
  final int fileCount;

  Map<String, Object?> toJson() => {'type': type.name, 'path': relativePath, 'bytes': byteCount, 'files': fileCount};

  factory BackupManifestEntry.fromJson(Map<String, dynamic> json) => BackupManifestEntry(
    type: BackupDataType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => throw FormatException('Unknown backup data type ${json['type']}'),
    ),
    relativePath: json['path'] as String,
    byteCount: json['bytes'] as int,
    fileCount: json['files'] as int,
  );
}
