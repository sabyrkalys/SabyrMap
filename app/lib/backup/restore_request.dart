import 'backup_data_type.dart';

/// Что восстановить из архива.
class RestoreRequest {
  const RestoreRequest({
    required this.sourcePath,
    required this.types,
    this.overwriteExisting = false,
    this.includeSettings = false,
  });

  final String sourcePath;
  final Set<BackupDataType> types;

  /// Да — сначала удалить данные выбранных типов; нет — не трогать
  /// существующие файлы.
  final bool overwriteExisting;

  /// Восстановить все настройки (как тип [BackupDataType.settings]).
  final bool includeSettings;

  Set<BackupDataType> get effectiveTypes => {...types, if (includeSettings) BackupDataType.settings};
}
