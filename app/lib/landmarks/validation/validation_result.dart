/// Итог проверки черновика или правки.
class ValidationResult {
  const ValidationResult._(this.errors);

  factory ValidationResult.success() => const ValidationResult._([]);
  factory ValidationResult.failure(List<String> errors) => ValidationResult._(List.unmodifiable(errors));

  /// Что не так; пусто, если всё в порядке.
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

/// Черновик или правка не прошли проверку.
class ValidationException implements Exception {
  const ValidationException(this.errors);

  final List<String> errors;

  @override
  String toString() => 'ValidationException: ${errors.join('; ')}';
}
