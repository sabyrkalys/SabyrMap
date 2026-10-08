import '../../catalog/catalog_repository.dart';
import '../../models/map_models.dart';

/// What a map shows: picks the card placeholder and drives «Только
/// спутниковые».
enum MapKind { scheme, terrain, hybrid, satellite }

MapKind mapKindOf(MapSource source) {
  final id = source.id.toLowerCase();
  if (id.contains('hybrid')) return MapKind.hybrid;
  if (id.contains('satellite') || id.endsWith('-sat')) return MapKind.satellite;
  if (id.contains('terrain')) return MapKind.terrain;
  return MapKind.scheme;
}

/// A titled accordion in the list: catalog providers regrouped for display.
class MapGroup {
  const MapGroup({required this.id, required this.title, required this.providers});

  final String id;
  final String title;
  final List<MapProvider> providers;

  List<MapSource> get sources => [for (final p in providers) ...p.sources];
}

/// Display group id and title for a catalog provider. Our own server's maps
/// sit under «GOOGLE MAPS» for now.
(String, String) _groupOf(MapProvider provider) => switch (provider.id) {
  'osm' => ('osm', 'OPENSTREETMAP'),
  CatalogRepository.serverProviderId || 'google' => ('google', 'GOOGLE MAPS'),
  CatalogRepository.localProviderId => (ownGroupId, ownGroupTitle),
  _ => (provider.id, provider.name.toUpperCase()),
};

/// Installed maps whose source is unknown: the user's own files and style
/// URLs. Downloaded maps of a known source sit in that source's group.
const ownGroupId = 'own';
const ownGroupTitle = 'СВОИ КАРТЫ';

/// Online groups first (OpenStreetMap, Google Maps, then the rest in catalog
/// order); installed maps are placed by the screen.
List<MapGroup> groupProviders(List<MapProvider> providers) {
  final byId = <String, (String, List<MapProvider>)>{};
  for (final provider in providers) {
    final (id, title) = _groupOf(provider);
    if (id == ownGroupId) continue;
    byId.putIfAbsent(id, () => (title, [])).$2.add(provider);
  }
  const order = ['osm', 'google'];
  final ids = [...order.where(byId.containsKey), ...byId.keys.where((id) => !order.contains(id))];
  return [for (final id in ids) MapGroup(id: id, title: byId[id]!.$1, providers: byId[id]!.$2)];
}

/// A folder under «КАРТЫ НА УСТРОЙСТВЕ» in the side drawer.
class DeviceFolder {
  const DeviceFolder({required this.name, required this.path});

  final String name;
  final String path;
}

/// Space on the volume holding the maps folder.
class StorageUsage {
  const StorageUsage({required this.path, required this.usedBytes, required this.totalBytes});

  final String path;
  final int usedBytes;
  final int totalBytes;

  double get fraction => totalBytes == 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0);

  /// «238 ГБ / 487 ГБ».
  String get label => '${_gb(usedBytes)} ГБ / ${_gb(totalBytes)} ГБ';

  static int _gb(int bytes) => (bytes / (1024 * 1024 * 1024)).round();
}

/// Sections switched from the side drawer.
enum MapsSection {
  available('Установленные карты'),
  altitude('Высота над уровнем моря');

  const MapsSection(this.label);

  final String label;
}

/// Checkboxes of the «Фильтр» dialog.
class MapsFilter {
  const MapsFilter({this.onlyDownloaded = false, this.onlySatellite = false});

  final bool onlyDownloaded;
  final bool onlySatellite;

  bool get isActive => onlyDownloaded || onlySatellite;

  /// [cacheBytes]: saved areas of [source] on the device.
  bool accepts(MapSource source, int cacheBytes) {
    final downloaded = cacheBytes > 0 || source.storageMode == StorageMode.offlineRegion;
    final kind = mapKindOf(source);
    return (!onlyDownloaded || downloaded) && (!onlySatellite || kind == MapKind.satellite || kind == MapKind.hybrid);
  }
}

// Stub until the app opens the device's file browser.

const mockDeviceFolders = [
  DeviceFolder(name: 'SabyrMap Maps', path: '/SabyrMap/Maps/'),
  DeviceFolder(name: 'Медиафайлы', path: 'Android/media/com.sabyrmap.app/'),
  DeviceFolder(name: 'Мои загрузки', path: 'Download/'),
];
