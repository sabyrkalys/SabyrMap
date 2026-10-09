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

import 'gpx_parser.dart';
import 'gpx_serializer.dart';

const List<String> _elevationValues = ['none', 'wgs84', 'egm96'];

/// Импорт GPX.
class GpxImportAdapter extends ImportAdapter {
  const GpxImportAdapter();

  @override
  String get formatId => GpxAdapter.id;

  @override
  ImportOptionsSchema get optionsSchema => const ImportOptionsSchema(
    fields: [
      ImportOptionField(
        id: GpxParser.includeWaypointsInTrack,
        label: 'Прикрепить точки к треку',
        type: OptionFieldType.boolean,
        defaultValue: true,
      ),
      ImportOptionField(
        id: 'elevationSource',
        label: 'Высоты',
        type: OptionFieldType.enumeration,
        defaultValue: 'wgs84',
        values: _elevationValues,
      ),
    ],
  );

  @override
  Future<List<LandmarkObject>> parse(Uint8List bytes, ImportOptions options, {WarningSink? onWarning}) async =>
      const GpxParser().parse(bytes, options, onWarning: onWarning);
}

/// Экспорт GPX.
class GpxExportAdapter extends ExportAdapter {
  const GpxExportAdapter();

  @override
  String get formatId => GpxAdapter.id;

  @override
  ExportOptionsSchema get optionsSchema => const ExportOptionsSchema(
    fields: [
      ExportOptionField(
        id: 'includeWaypoints',
        label: 'Точки трека',
        type: OptionFieldType.boolean,
        defaultValue: true,
      ),
      ExportOptionField(
        id: 'includeSegments',
        label: 'Сегменты трека',
        type: OptionFieldType.boolean,
        defaultValue: true,
      ),
      ExportOptionField(
        id: GpxSerializer.elevationSource,
        label: 'Высоты',
        type: OptionFieldType.enumeration,
        defaultValue: 'wgs84',
        values: _elevationValues,
      ),
    ],
  );

  @override
  Future<Uint8List> serialize(List<LandmarkObject> objects, ExportOptions options, {WarningSink? onWarning}) async =>
      const GpxSerializer().serialize(objects, options, onWarning: onWarning);

  @override
  String extensionFor(ExportOptions options) => 'gpx';
}

/// Формат GPX в реестре.
abstract final class GpxAdapter {
  static const String id = 'gpx';

  static FormatDescriptor descriptor() => FormatDescriptor(
    id: id,
    displayName: 'GPX',
    extensions: const ['gpx'],
    capabilities: const {
      FormatCapability.importWaypoint,
      FormatCapability.importRoute,
      FormatCapability.importTrack,
      FormatCapability.exportWaypoint,
      FormatCapability.exportRoute,
      FormatCapability.exportTrack,
      FormatCapability.hasOptions,
      FormatCapability.requiresCharset,
      FormatCapability.supportsStyle,
      FormatCapability.multiObjectPerFile,
    },
    importAdapter: const GpxImportAdapter(),
    exportAdapter: const GpxExportAdapter(),
  );

}
