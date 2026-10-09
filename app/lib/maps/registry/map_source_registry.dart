import 'map_format_capability.dart';
import 'map_source_descriptor.dart';
import 'map_source_kind.dart';

/// Форматы и источники карт. Новые добавляются через [register].
class MapSourceRegistry {
  final Map<String, MapSourceDescriptor> _byId = {};

  /// Регистрирует; тот же id заменяет прежний.
  void register(MapSourceDescriptor descriptor) => _byId[descriptor.id] = descriptor;

  MapSourceDescriptor? byId(String id) => _byId[id];

  /// Первый зарегистрированный формат с расширением [ext].
  MapSourceDescriptor? byExtension(String ext) {
    final normalized = MapSourceDescriptor.normalizeExtension(ext);
    return _byId.values.where((d) => d.extensions.contains(normalized)).firstOrNull;
  }

  List<MapSourceDescriptor> byKind(MapSourceKind kind) =>
      List.unmodifiable(_byId.values.where((d) => d.kind == kind));

  List<MapSourceDescriptor> get all => List.unmodifiable(_byId.values);

  /// Файловые растровые карты: прозрачность, цвет, стирание цвета, слои.
  static const Set<MapFormatCapability> _fileRaster = {
    MapFormatCapability.raster,
    MapFormatCapability.offlineCapable,
    MapFormatCapability.supportsOpacity,
    MapFormatCapability.supportsColorCorrection,
    MapFormatCapability.supportsEraseColor,
    MapFormatCapability.supportsMultipleLayers,
  };

  /// Встроенные форматы. Decision: ZIP-XYZ и ZIP-TMS оба на `.zip`;
  /// по расширению находится XYZ (порядок регистрации), TMS — по id.
  static MapSourceRegistry buildDefault() {
    MapSourceDescriptor file(String id, String name, List<String> ext, {bool calibration = false}) =>
        MapSourceDescriptor(
          id: id,
          displayName: name,
          kind: MapSourceKind.fileBased,
          extensions: ext,
          capabilities: {..._fileRaster, if (calibration) MapFormatCapability.supportsCalibration},
        );
    return MapSourceRegistry()
      ..register(file('aqm', 'AQM', const ['aqm']))
      ..register(file('pgd', 'PGD', const ['pgd']))
      ..register(file('gpkg', 'GeoPackage', const ['gpkg']))
      ..register(file('map', 'MAP (calibrated image)', const ['map'], calibration: true))
      ..register(file('rmap', 'RMAP', const ['rmap']))
      ..register(file('qct', 'QCT', const ['qct']))
      ..register(file('mbtiles', 'MBTiles', const ['mbtiles']))
      ..register(file('sqlitedb', 'SQLiteDB', const ['sqlitedb']))
      ..register(file('zip-xyz', 'ZIP (XYZ tiles)', const ['zip']))
      ..register(file('zip-tms', 'ZIP (TMS tiles)', const ['zip']))
      ..register(file('tiff', 'GeoTIFF', const ['tif', 'tiff'], calibration: true))
      ..register(
        MapSourceDescriptor(
          id: 'kml-overlay',
          displayName: 'KML / KMZ overlay',
          kind: MapSourceKind.overlay,
          extensions: const ['kml', 'kmz'],
          capabilities: {..._fileRaster},
        ),
      )
      ..register(file('image', 'Image', const ['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'], calibration: true))
      ..register(
        MapSourceDescriptor(
          id: 'hgt',
          displayName: 'HGT elevation',
          kind: MapSourceKind.dem,
          extensions: const ['hgt'],
          capabilities: const {MapFormatCapability.offlineCapable},
        ),
      )
      ..register(
        MapSourceDescriptor(
          id: 'aqx',
          displayName: 'Online map (AQX)',
          kind: MapSourceKind.onDemand,
          extensions: const ['aqx'],
          capabilities: const {
            MapFormatCapability.raster,
            MapFormatCapability.onlineRequired,
            MapFormatCapability.supportsOpacity,
            MapFormatCapability.supportsColorCorrection,
            MapFormatCapability.supportsEraseColor,
            MapFormatCapability.supportsMultipleLayers,
          },
        ),
      );
  }
}
