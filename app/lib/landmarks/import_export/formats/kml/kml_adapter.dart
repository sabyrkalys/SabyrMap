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

import 'kml_parser.dart';
import 'kml_serializer.dart';

/// Импорт KML/KMZ.
class KmlImportAdapter extends ImportAdapter {
  const KmlImportAdapter();

  @override
  String get formatId => KmlAdapter.id;

  @override
  ImportOptionsSchema get optionsSchema => const ImportOptionsSchema(
    fields: [
      ImportOptionField(
        id: 'elevationSource',
        label: 'Высоты',
        type: OptionFieldType.enumeration,
        defaultValue: 'wgs84',
        values: ['none', 'wgs84', 'egm96'],
      ),
    ],
  );

  @override
  Future<List<LandmarkObject>> parse(Uint8List bytes, ImportOptions options, {WarningSink? onWarning}) async =>
      const KmlParser().parse(bytes, options, onWarning: onWarning);
}

/// Экспорт KML/KMZ.
class KmlExportAdapter extends ExportAdapter {
  const KmlExportAdapter();

  @override
  String get formatId => KmlAdapter.id;

  @override
  ExportOptionsSchema get optionsSchema => const ExportOptionsSchema(
    fields: [
      ExportOptionField(id: KmlSerializer.asKmz, label: 'KMZ', type: OptionFieldType.boolean, defaultValue: false),
      ExportOptionField(
        id: KmlSerializer.embedPictures,
        label: 'Вложить картинки (KMZ)',
        type: OptionFieldType.boolean,
        defaultValue: false,
      ),
      ExportOptionField(
        id: 'includeSegments',
        label: 'Сегменты трека',
        type: OptionFieldType.boolean,
        defaultValue: true,
      ),
      ExportOptionField(
        id: 'includeWaypoints',
        label: 'Точки трека',
        type: OptionFieldType.boolean,
        defaultValue: true,
      ),
    ],
  );

  @override
  Future<Uint8List> serialize(List<LandmarkObject> objects, ExportOptions options, {WarningSink? onWarning}) async =>
      const KmlSerializer().serialize(objects, options, onWarning: onWarning);

  @override
  String extensionFor(ExportOptions options) => options.extra(KmlSerializer.asKmz, false) ? 'kmz' : 'kml';
}

/// Формат KML/KMZ в реестре.
abstract final class KmlAdapter {
  static const String id = 'kml';

  static FormatDescriptor descriptor() => FormatDescriptor(
    id: id,
    displayName: 'KML / KMZ',
    extensions: const ['kml', 'kmz'],
    capabilities: const {
      FormatCapability.importWaypoint,
      FormatCapability.importRoute,
      FormatCapability.importTrack,
      FormatCapability.importArea,
      FormatCapability.exportWaypoint,
      FormatCapability.exportRoute,
      FormatCapability.exportTrack,
      FormatCapability.exportArea,
      FormatCapability.hasOptions,
      FormatCapability.supportsStyle,
      FormatCapability.multiObjectPerFile,
    },
    importAdapter: const KmlImportAdapter(),
    exportAdapter: const KmlExportAdapter(),
  );
}
