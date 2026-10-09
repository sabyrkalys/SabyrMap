/// Операция с папкой недопустима или не удалась (уже существует,
/// защищённая папка, вставка в саму себя…).
class FolderException implements Exception {
  const FolderException(this.message, {this.path});

  final String message;
  final String? path;

  @override
  String toString() => path == null ? 'FolderException: $message' : 'FolderException: $message ($path)';
}
