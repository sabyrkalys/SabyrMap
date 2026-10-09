import 'package:app/landmarks/import_export/formats/csv/csv_adapter.dart';
import 'package:app/landmarks/import_export/formats/geojson/geojson_adapter.dart';
import 'package:app/landmarks/import_export/formats/gpx/gpx_adapter.dart';
import 'package:app/landmarks/import_export/formats/kml/kml_adapter.dart';
import 'package:app/landmarks/models/landmark_type.dart';

import 'format_capability.dart';
import 'format_descriptor.dart';

/// Форматы импорта и экспорта. Новые форматы добавляются через
/// [register] — без правки сервисов.
class FormatRegistry {
  final Map<String, FormatDescriptor> _byId = {};

  /// Регистрирует формат; тот же id заменяет прежний.
  void register(FormatDescriptor descriptor) => _byId[descriptor.id] = descriptor;

  FormatDescriptor? byId(String id) => _byId[id];

  /// Формат по расширению (с точкой или без, любой регистр).
  FormatDescriptor? byExtension(String ext) {
    final normalized = FormatDescriptor.normalizeExtension(ext);
    return _byId.values.where((d) => d.extensions.contains(normalized)).firstOrNull;
  }

  /// Все форматы в порядке регистрации.
  List<FormatDescriptor> get all => List.unmodifiable(_byId.values);
  List<FormatDescriptor> get importers => List.unmodifiable(_byId.values.where((d) => d.canImport));
  List<FormatDescriptor> get exporters => List.unmodifiable(_byId.values.where((d) => d.canExport));

  /// Форматы, в которые можно экспортировать объект типа [type].
  /// Decision: «для объекта» — значит для экспорта: так меню «Экспорт»
  /// показывает только подходящие форматы.
  List<FormatDescriptor> forObject(LandmarkType type) => List.unmodifiable(
    _byId.values.where((d) => d.canExport && d.supports(FormatCapability.exportOf(type))),
  );

  /// GPX, KML/KMZ, CSV/TSV и GeoJSON.
  static FormatRegistry buildDefault() => FormatRegistry()
    ..register(GpxAdapter.descriptor())
    ..register(KmlAdapter.descriptor())
    ..register(CsvAdapter.descriptor())
    ..register(GeoJsonAdapter.descriptor());
}
