/// Ошибка файлового хранилища: нет доступа, файл не найден, сбой записи.
class StorageException implements Exception {
  const StorageException(this.message, {this.path, this.cause});

  /// Что пошло не так, человеческим языком.
  final String message;

  /// Путь, с которым работали, если он известен.
  final String? path;

  /// Исходная ошибка (обычно [FileSystemException]), если есть.
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('StorageException: $message');
    if (path != null) buffer.write(' (path: $path)');
    if (cause != null) buffer.write(' — caused by: $cause');
    return buffer.toString();
  }
}
