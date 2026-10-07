import '../config.dart';

/// What a map shows, used by the «Фильтр» dialog.
enum MapKind { scheme, terrain, hybrid, satellite }

/// One map of an online source, as a card in the list.
class OnlineMap {
  const OnlineMap({
    required this.id,
    required this.name,
    required this.size,
    required this.previewUrl,
    required this.kind,
  });

  final String id;
  final String name;

  /// Size of the cached tiles, already formatted («68,79 КБ»), or «Нет».
  final String size;

  /// Path on our server: /api/maps/{sourceId}/preview/{mapId}.jpg.
  final String previewUrl;
  final MapKind kind;

  bool get isDownloaded => size != 'Нет';

  String get resolvedPreviewUrl => '${AppConfig.apiBaseUrl}$previewUrl';
}

/// A provider group in the list. Only OpenStreetMap is fetched from OSM;
/// every other source is served by our own backend under a familiar name.
class OnlineMapSource {
  const OnlineMapSource({required this.id, required this.title, this.subtitle, required this.maps});

  final String id;
  final String title;
  final String? subtitle;
  final List<OnlineMap> maps;
}

/// A folder under «КАРТЫ НА УСТРОЙСТВЕ» in the side drawer.
class DeviceFolder {
  const DeviceFolder({required this.name, required this.path});

  final String name;
  final String path;
}

class StorageUsage {
  const StorageUsage({required this.path, required this.usedGb, required this.totalGb});

  final String path;
  final int usedGb;
  final int totalGb;

  double get fraction => totalGb == 0 ? 0 : usedGb / totalGb;
}

/// Sections switched from the side drawer.
enum OnlineMapsSection {
  installed('Установленные карты'),
  altitude('Высота над уровнем моря');

  const OnlineMapsSection(this.label);

  final String label;
}

/// Checkboxes of the «Фильтр» dialog.
class OnlineMapsFilter {
  const OnlineMapsFilter({this.onlyDownloaded = false, this.onlySatellite = false});

  final bool onlyDownloaded;
  final bool onlySatellite;

  bool accepts(OnlineMap map) =>
      (!onlyDownloaded || map.isDownloaded) && (!onlySatellite || map.kind == MapKind.satellite);
}

// Mock data until the screen is wired to the server catalog.

const mockStorageUsage = StorageUsage(path: '/storage/emulated/0/', usedGb: 238, totalGb: 487);

const mockDeviceFolders = [
  DeviceFolder(name: 'AlpineQuest Maps', path: '/pinequest.free/AlpineQuest Maps/'),
  DeviceFolder(name: 'Медиафайлы', path: 'Android/media/psyberia.alpinequest/'),
  DeviceFolder(name: 'Мои загрузки', path: 'Download/'),
];

const mockMapSources = [
  OnlineMapSource(
    id: 'osm',
    title: 'OPENSTREETMAP',
    subtitle: '© OpenStreetMap contributors',
    maps: [
      OnlineMap(
        id: 'osm-standard',
        name: 'OpenStreetMap',
        size: 'Нет',
        previewUrl: '/api/maps/osm/preview/standard.jpg',
        kind: MapKind.scheme,
      ),
    ],
  ),
  OnlineMapSource(
    id: 'google',
    title: 'GOOGLE MAPS',
    subtitle: '105 МБ · © Google · www.google.com/maps',
    maps: [
      OnlineMap(
        id: 'gmap',
        name: 'Google Map',
        size: 'Нет',
        previewUrl: '/api/maps/google/preview/map.jpg',
        kind: MapKind.scheme,
      ),
      OnlineMap(
        id: 'gbike',
        name: 'Google Bike',
        size: '68,79 КБ',
        previewUrl: '/api/maps/google/preview/bike.jpg',
        kind: MapKind.scheme,
      ),
      OnlineMap(
        id: 'gterrain',
        name: 'Google Terrain',
        size: 'Нет',
        previewUrl: '/api/maps/google/preview/terrain.jpg',
        kind: MapKind.terrain,
      ),
      OnlineMap(
        id: 'ghybrid',
        name: 'Google Hybrid',
        size: 'Нет',
        previewUrl: '/api/maps/google/preview/hybrid.jpg',
        kind: MapKind.hybrid,
      ),
      OnlineMap(
        id: 'gsat',
        name: 'Google Satellite',
        size: '64,01 МБ',
        previewUrl: '/api/maps/google/preview/satellite.jpg',
        kind: MapKind.satellite,
      ),
    ],
  ),
  OnlineMapSource(
    id: 'bing',
    title: 'BING MAPS',
    subtitle: '© Microsoft',
    maps: [
      OnlineMap(
        id: 'bing-road',
        name: 'Bing Road',
        size: 'Нет',
        previewUrl: '/api/maps/bing/preview/road.jpg',
        kind: MapKind.scheme,
      ),
      OnlineMap(
        id: 'bing-aerial',
        name: 'Bing Aerial',
        size: 'Нет',
        previewUrl: '/api/maps/bing/preview/aerial.jpg',
        kind: MapKind.satellite,
      ),
    ],
  ),
  OnlineMapSource(
    id: 'here',
    title: 'HERE MAPS',
    subtitle: '© HERE',
    maps: [
      OnlineMap(
        id: 'here-normal',
        name: 'HERE Normal',
        size: 'Нет',
        previewUrl: '/api/maps/here/preview/normal.jpg',
        kind: MapKind.scheme,
      ),
    ],
  ),
  OnlineMapSource(
    id: 'yandex',
    title: 'YANDEX MAPS',
    subtitle: '© Яндекс',
    maps: [
      OnlineMap(
        id: 'yandex-map',
        name: 'Яндекс.Карта',
        size: 'Нет',
        previewUrl: '/api/maps/yandex/preview/map.jpg',
        kind: MapKind.scheme,
      ),
      OnlineMap(
        id: 'yandex-sat',
        name: 'Яндекс.Спутник',
        size: 'Нет',
        previewUrl: '/api/maps/yandex/preview/sat.jpg',
        kind: MapKind.satellite,
      ),
    ],
  ),
];
