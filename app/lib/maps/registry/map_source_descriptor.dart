import 'map_format_capability.dart';
import 'map_source_kind.dart';

/// Формат или источник карты в реестре.
class MapSourceDescriptor {
  MapSourceDescriptor({
    required this.id,
    required this.displayName,
    required this.kind,
    required List<String> extensions,
    required this.capabilities,
    this.configPath,
  }) : extensions = List.unmodifiable(extensions.map(normalizeExtension));

  final String id;
  final String displayName;
  final MapSourceKind kind;

  /// Без точки, в нижнем регистре.
  final List<String> extensions;
  final Set<MapFormatCapability> capabilities;

  /// Файл описания (для онлайн-карт).
  final String? configPath;

  bool has(MapFormatCapability cap) => capabilities.contains(cap);
  bool get isOnlineRequired => has(MapFormatCapability.onlineRequired);

  static String normalizeExtension(String ext) => (ext.startsWith('.') ? ext.substring(1) : ext).toLowerCase();

  @override
  String toString() => 'MapSourceDescriptor($id)';
}
