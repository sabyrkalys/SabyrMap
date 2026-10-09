import 'dart:typed_data';

import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/export/export_options_schema.dart';
import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/import_export/import/import_options_schema.dart';
import 'package:app/landmarks/import_export/registry/export_adapter.dart';
import 'package:app/landmarks/import_export/registry/format_capability.dart';
import 'package:app/landmarks/import_export/registry/format_descriptor.dart';
import 'package:app/landmarks/import_export/registry/import_adapter.dart';
import 'package:app/landmarks/models/landmark_object.dart';

import 'csv_parser.dart';
import 'csv_serializer.dart';

/// Импорт CSV/TSV.
class CsvImportAdapter extends ImportAdapter {
  const CsvImportAdapter();

  @override
  String get formatId => CsvAdapter.id;

  @override
  ImportOptionsSchema get optionsSchema => const ImportOptionsSchema(
    fields: [
      ImportOptionField(
        id: CsvParser.separator,
        label: 'Разделитель',
        type: OptionFieldType.enumeration,
        defaultValue: 'auto',
        values: ['auto', ',', ';', 'tab'],
      ),
      ImportOptionField(
        id: CsvParser.headersInFirstRow,
        label: 'Заголовки в первой строке',
        type: OptionFieldType.boolean,
        defaultValue: true,
      ),
      ImportOptionField(
        id: CsvParser.columns,
        label: 'Колонки (без заголовков)',
        type: OptionFieldType.string,
        defaultValue: CsvParser.defaultColumns,
      ),
      ImportOptionField(
        id: CsvParser.importAs,
        label: 'Создать',
        type: OptionFieldType.enumeration,
        defaultValue: 'auto',
        values: ['auto', 'waypoints', 'track'],
      ),
    ],
  );

  @override
  Future<List<LandmarkObject>> parse(Uint8List bytes, ImportOptions options, {WarningSink? onWarning}) async =>
      const CsvParser().parse(bytes, options, onWarning: onWarning);
}

/// Экспорт CSV/TSV.
class CsvExportAdapter extends ExportAdapter {
  const CsvExportAdapter();

  @override
  String get formatId => CsvAdapter.id;

  @override
  ExportOptionsSchema get optionsSchema => const ExportOptionsSchema(
    fields: [
      ExportOptionField(
        id: CsvSerializer.separator,
        label: 'Разделитель',
        type: OptionFieldType.enumeration,
        defaultValue: ',',
        values: [',', ';', 'tab'],
      ),
      ExportOptionField(
        id: CsvSerializer.headersInFirstRow,
        label: 'Заголовки в первой строке',
        type: OptionFieldType.boolean,
        defaultValue: true,
      ),
      ExportOptionField(
        id: CsvSerializer.columns,
        label: 'Колонки',
        type: OptionFieldType.string,
        defaultValue: CsvSerializer.defaultColumns,
        values: CsvSerializer.knownColumns,
      ),
      ExportOptionField(
        id: CsvSerializer.timeFormat,
        label: 'Формат времени',
        type: OptionFieldType.enumeration,
        defaultValue: 'iso',
        values: ['iso', 'unix'],
      ),
    ],
  );

  @override
  Future<Uint8List> serialize(List<LandmarkObject> objects, ExportOptions options, {WarningSink? onWarning}) async =>
      const CsvSerializer().serialize(objects, options, onWarning: onWarning);

  /// Табуляция — `.tsv`, иначе `.csv`.
  @override
  String extensionFor(ExportOptions options) =>
      const {'tab', '\\t', '\t'}.contains(options.extra<String>(CsvSerializer.separator, ',')) ? 'tsv' : 'csv';
}

/// Формат CSV/TSV в реестре.
abstract final class CsvAdapter {
  static const String id = 'csv';

  static FormatDescriptor descriptor() => FormatDescriptor(
    id: id,
    displayName: 'CSV / TSV',
    extensions: const ['csv', 'tsv'],
    capabilities: const {
      FormatCapability.importWaypoint,
      FormatCapability.importTrack,
      FormatCapability.exportWaypoint,
      FormatCapability.exportTrack,
      FormatCapability.hasOptions,
      FormatCapability.requiresCharset,
      FormatCapability.multiObjectPerFile,
    },
    importAdapter: const CsvImportAdapter(),
    exportAdapter: const CsvExportAdapter(),
  );
}
