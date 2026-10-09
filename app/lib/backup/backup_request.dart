import 'backup_data_type.dart';

/// Что и куда сохранить.
class BackupRequest {
  const BackupRequest({
    required this.targetPath,
    required this.types,
    this.includeFullLandmarks = true,
    this.includedFolders = const [],
    this.includeSettings = false,
  });

  /// Расширение файла резервной копии.
  static const String extension = '.saby-backup.zip';

  /// Абсолютный путь итогового архива.
  final String targetPath;
  final Set<BackupDataType> types;

  /// Все метки; нет — только папки [includedFolders].
  final bool includeFullLandmarks;

  /// Папки меток (абсолютные, внутри `<корень>/landmarks`).
  final List<String> includedFolders;

  /// Добавить все настройки (как тип [BackupDataType.settings]).
  final bool includeSettings;

  /// Типы с учётом [includeSettings].
  Set<BackupDataType> get effectiveTypes => {...types, if (includeSettings) BackupDataType.settings};
}
