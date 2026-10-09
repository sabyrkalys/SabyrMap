import 'dart:convert';

import 'backup_manifest_entry.dart';

/// `manifest.json` резервной копии.
class BackupManifest {
  const BackupManifest({
    this.version = currentVersion,
    required this.createdAt,
    required this.appVersion,
    required this.entries,
  });

  static const int currentVersion = 1;
  static const String fileName = 'manifest.json';

  final int version;

  /// Unix ms.
  final int createdAt;
  final String appVersion;
  final List<BackupManifestEntry> entries;

  Map<String, Object?> toJson() => {
    'version': version,
    'createdAt': createdAt,
    'appVersion': appVersion,
    'entries': [for (final e in entries) e.toJson()],
  };

  /// Из JSON; неверная запись — [FormatException].
  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    try {
      return BackupManifest(
        version: json['version'] as int,
        createdAt: json['createdAt'] as int,
        appVersion: json['appVersion'] as String,
        entries: [
          for (final e in json['entries'] as List<dynamic>) BackupManifestEntry.fromJson(e as Map<String, dynamic>),
        ],
      );
    } on TypeError catch (e) {
      throw FormatException('Invalid backup manifest: $e');
    }
  }

  static BackupManifest decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('Invalid backup manifest: ${e.message}');
    }
    if (json is! Map<String, dynamic>) throw const FormatException('Invalid backup manifest');
    return BackupManifest.fromJson(json);
  }
}
