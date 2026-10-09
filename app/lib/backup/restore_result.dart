/// Итог восстановления.
class RestoreResult {
  const RestoreResult({
    required this.success,
    this.restoredFiles = 0,
    this.warnings = const [],
    this.errorMessage,
    this.needsRestart = false,
  });

  factory RestoreResult.failure(String message, {List<String> warnings = const [], int restoredFiles = 0}) =>
      RestoreResult(success: false, errorMessage: message, warnings: warnings, restoredFiles: restoredFiles);

  final bool success;
  final int restoredFiles;
  final List<String> warnings;
  final String? errorMessage;

  /// Восстановлены настройки — приложению нужен перезапуск.
  final bool needsRestart;
}
