import 'detail_data.dart';

/// Строка «подпись — значение» в секции детализации.
class DetailField {
  const DetailField({required this.label, required this.valueResolver, this.isMultiline = false});

  final String label;

  /// Значение из данных детализации.
  ///
  /// Decision: на вход — [LandmarkDetailsData], а не только элемент списка:
  /// координаты, сегменты и плечи есть лишь в содержимом файла.
  final String Function(LandmarkDetailsData data) valueResolver;

  /// Длинное значение (путь) переносится по строкам.
  final bool isMultiline;
}
