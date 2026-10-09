import 'package:app/landmarks/models/landmark_type.dart';

/// Итог импорта.
class ImportResult {
  const ImportResult({
    required this.success,
    this.createdPaths = const [],
    this.createdTypes = const [],
    this.warnings = const [],
    this.errorMessage,
  });

  factory ImportResult.failure(String message, {List<String> warnings = const []}) =>
      ImportResult(success: false, errorMessage: message, warnings: warnings);

  final bool success;

  /// Созданные файлы меток и их типы (в одном порядке).
  final List<String> createdPaths;
  final List<LandmarkType> createdTypes;
  final List<String> warnings;
  final String? errorMessage;

  int get importedCount => createdPaths.length;

  @override
  String toString() => success
      ? 'ImportResult($importedCount imported, ${warnings.length} warning(s))'
      : 'ImportResult(failed: $errorMessage)';
}
