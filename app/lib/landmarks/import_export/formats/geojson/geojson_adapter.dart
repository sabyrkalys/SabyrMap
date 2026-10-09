import 'dart:typed_data';

import 'package:app/landmarks/import_export/import/import_options.dart';
import 'package:app/landmarks/import_export/import/import_options_schema.dart';
import 'package:app/landmarks/import_export/registry/format_capability.dart';
import 'package:app/landmarks/import_export/registry/format_descriptor.dart';
import 'package:app/landmarks/import_export/registry/import_adapter.dart';
import 'package:app/landmarks/models/landmark_object.dart';

import 'geojson_parser.dart';

/// Импорт GeoJSON (экспорта в этой версии нет).
class GeoJsonImportAdapter extends ImportAdapter {
  const GeoJsonImportAdapter();

  @override
  String get formatId => GeoJsonAdapter.id;

  @override
  ImportOptionsSchema get optionsSchema => const ImportOptionsSchema();

  @override
  Future<List<LandmarkObject>> parse(Uint8List bytes, ImportOptions options, {WarningSink? onWarning}) async =>
      const GeoJsonParser().parse(bytes, options, onWarning: onWarning);
}

/// Формат GeoJSON в реестре.
abstract final class GeoJsonAdapter {
  static const String id = 'geojson';

  static FormatDescriptor descriptor() => FormatDescriptor(
    id: id,
    displayName: 'GeoJSON',
    extensions: const ['geojson', 'json'],
    capabilities: const {
      FormatCapability.importWaypoint,
      FormatCapability.importRoute,
      FormatCapability.importTrack,
      FormatCapability.importArea,
      FormatCapability.multiObjectPerFile,
    },
    importAdapter: const GeoJsonImportAdapter(),
  );
}
