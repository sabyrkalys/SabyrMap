/// Итог операции проводника над одним или несколькими файлами.
class OperationResult {
  const OperationResult({required this.success, required this.affectedCount, this.errorMessage});

  factory OperationResult.ok(int count) => OperationResult(success: true, affectedCount: count);

  factory OperationResult.failed(String message) =>
      OperationResult(success: false, affectedCount: 0, errorMessage: message);

  /// Итог групповой операции: успех, только если ошибок нет; число
  /// обработанных — сколько получилось; ошибки — через «; ».
  factory OperationResult.of(int affected, List<String> errors) => OperationResult(
    success: errors.isEmpty,
    affectedCount: affected,
    errorMessage: errors.isEmpty ? null : errors.join('; '),
  );

  final bool success;

  /// Сколько файлов обработано успешно.
  final int affectedCount;
  final String? errorMessage;

  @override
  String toString() => success ? 'OperationResult.ok($affectedCount)' : 'OperationResult.failed($affectedCount, $errorMessage)';
}
