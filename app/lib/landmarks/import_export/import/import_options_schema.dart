/// Тип поля опции.
enum OptionFieldType { boolean, string, enumeration }

/// Одна опция импорта или экспорта для UI.
class ImportOptionField {
  const ImportOptionField({
    required this.id,
    required this.label,
    required this.type,
    this.defaultValue,
    this.values = const [],
  });

  /// Ключ в `extras` (или имя общего поля опций).
  final String id;
  final String label;
  final OptionFieldType type;
  final Object? defaultValue;

  /// Варианты для [OptionFieldType.enumeration].
  final List<String> values;
}

/// Опции формата для UI.
class ImportOptionsSchema {
  const ImportOptionsSchema({this.fields = const []});

  final List<ImportOptionField> fields;

  /// Значения по умолчанию по id.
  Map<String, Object?> get defaults => {for (final f in fields) f.id: f.defaultValue};

  ImportOptionField? field(String id) => fields.where((f) => f.id == id).firstOrNull;
}
