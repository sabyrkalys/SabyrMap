/// Итог резервного копирования.
class BackupResult {
  const BackupResult({
    required this.success,
    this.filePath,
    this.totalBytes = 0,
    this.totalFiles = 0,
    this.errorMessage,
    this.warnings = const [],
  });

  factory BackupResult.failure(String message, {List<String> warnings = const []}) =>
      BackupResult(success: false, errorMessage: message, warnings: warnings);

  final bool success;
  final String? filePath;

  /// Данные до сжатия.
  final int totalBytes;
  final int totalFiles;
  final String? errorMessage;
  final List<String> warnings;
}
