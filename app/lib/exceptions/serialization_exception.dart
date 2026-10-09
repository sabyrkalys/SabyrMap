/// Ошибка чтения или записи двоичного формата меток: повреждённый или
/// обрезанный файл, неизвестный тип значения, число вне диапазона.
class SerializationException implements Exception {
  const SerializationException(this.message, {this.position, this.cause});

  /// Что пошло не так.
  final String message;

  /// Смещение в байтах, на котором обнаружена ошибка, если известно.
  final int? position;

  /// Исходная ошибка, если есть.
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('SerializationException: $message');
    if (position != null) buffer.write(' (at byte $position)');
    if (cause != null) buffer.write(' — caused by: $cause');
    return buffer.toString();
  }
}
