/// Итог экспорта.
class ExportResult {
  const ExportResult({
    required this.success,
    this.filePath,
    this.exportedCount = 0,
    this.errorMessage,
    this.warnings = const [],
  });

  factory ExportResult.failure(String message, {List<String> warnings = const []}) =>
      ExportResult(success: false, errorMessage: message, warnings: warnings);

  final bool success;

  /// Абсолютный путь созданного файла.
  final String? filePath;
  final int exportedCount;
  final String? errorMessage;
  final List<String> warnings;

  @override
  String toString() => success ? 'ExportResult($exportedCount → $filePath)' : 'ExportResult(failed: $errorMessage)';
}
