import 'package:app/landmarks/import_export/import/import_options_schema.dart';

export 'package:app/landmarks/import_export/import/import_options_schema.dart' show OptionFieldType;

/// Поле опции экспорта (устроено как поле импорта).
typedef ExportOptionField = ImportOptionField;

/// Опции экспорта формата для UI.
class ExportOptionsSchema {
  const ExportOptionsSchema({this.fields = const []});

  final List<ExportOptionField> fields;

  Map<String, Object?> get defaults => {for (final f in fields) f.id: f.defaultValue};

  ExportOptionField? field(String id) => fields.where((f) => f.id == id).firstOrNull;
}
