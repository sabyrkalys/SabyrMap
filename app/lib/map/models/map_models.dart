import 'package:collection/collection.dart';

/// How a source's tiles may be kept on the device.
enum StorageMode {
  /// Online only, never downloaded for offline use (Google, Яндекс).
  onlineOnly,

  /// Normal tile cache, plus optional offline regions (OpenFreeMap).
  onlineCache,

  /// Only a local file (user .mbtiles).
  offlineRegion,
}

enum TileFormat { vector, raster }

enum MapLayerType { base, overlay }

T _enumByName<T extends Enum>(List<T> values, Object? name, String field) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown $field "$name"');
}

const _mapEquality = MapEquality<String, String>();
const _listEquality = ListEquality<Object?>();

/// One map a user can show: a vector style or a raster tile template.
class MapSource {
  const MapSource({
    required this.id,
    required this.name,
    this.styleUrl,
    this.tileUrlTemplate,
    required this.format,
    required this.storageMode,
    this.attribution,
    this.minZoom = 0,
    this.maxZoom = 22,
    this.canBeOverlay = false,
    this.thumbnailAsset,
    this.defaultOpacity = 1.0,
    this.extraParams,
  });

  /// Unique; also the MapLibre source id.
  final String id;
  final String name;

  /// Vector sources: the style JSON URL.
  final String? styleUrl;

  /// Raster sources: a `{z}/{x}/{y}` template. Google builds its URL at run
  /// time from a session, so its template is null.
  final String? tileUrlTemplate;
  final TileFormat format;
  final StorageMode storageMode;

  /// Must be shown whenever the source is on screen (e.g. «© Google»).
  final String? attribution;
  final int minZoom;
  final int maxZoom;
  final bool canBeOverlay;
  final String? thumbnailAsset;

  /// Opacity when added as an overlay.
  final double defaultOpacity;

  /// Provider-specific settings (Google mapType/layerTypes, Яндекс layer).
  final Map<String, String>? extraParams;

  factory MapSource.fromJson(Map<String, dynamic> json) => MapSource(
        id: json['id'] as String,
        name: json['name'] as String,
        styleUrl: json['styleUrl'] as String?,
        tileUrlTemplate: json['tileUrlTemplate'] as String?,
        format: _enumByName(TileFormat.values, json['format'], 'format'),
        storageMode: _enumByName(StorageMode.values, json['storageMode'], 'storageMode'),
        attribution: json['attribution'] as String?,
        minZoom: (json['minZoom'] as num?)?.toInt() ?? 0,
        maxZoom: (json['maxZoom'] as num?)?.toInt() ?? 22,
        canBeOverlay: json['canBeOverlay'] as bool? ?? false,
        thumbnailAsset: json['thumbnailAsset'] as String?,
        defaultOpacity: (json['defaultOpacity'] as num?)?.toDouble() ?? 1.0,
        extraParams: (json['extraParams'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as String)),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (styleUrl != null) 'styleUrl': styleUrl,
        if (tileUrlTemplate != null) 'tileUrlTemplate': tileUrlTemplate,
        'format': format.name,
        'storageMode': storageMode.name,
        if (attribution != null) 'attribution': attribution,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'canBeOverlay': canBeOverlay,
        if (thumbnailAsset != null) 'thumbnailAsset': thumbnailAsset,
        'defaultOpacity': defaultOpacity,
        if (extraParams != null) 'extraParams': extraParams,
      };

  @override
  bool operator ==(Object other) =>
      other is MapSource &&
      other.id == id &&
      other.name == name &&
      other.styleUrl == styleUrl &&
      other.tileUrlTemplate == tileUrlTemplate &&
      other.format == format &&
      other.storageMode == storageMode &&
      other.attribution == attribution &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom &&
      other.canBeOverlay == canBeOverlay &&
      other.thumbnailAsset == thumbnailAsset &&
      other.defaultOpacity == defaultOpacity &&
      _mapEquality.equals(other.extraParams, extraParams);

  @override
  int get hashCode => Object.hash(id, name, styleUrl, tileUrlTemplate, format, storageMode, minZoom, maxZoom);
}

/// A group of sources from one supplier, shown as one section in the UI.
class MapProvider {
  const MapProvider({
    required this.id,
    required this.name,
    this.attribution,
    this.isolated = false,
    required this.sources,
  });

  final String id;
  final String name;
  final String? attribution;

  /// The provider's maps may not be shown together with other providers'
  /// maps (Google Maps Platform terms): only as the base, with the app's own
  /// data on top.
  final bool isolated;
  final List<MapSource> sources;

  factory MapProvider.fromJson(Map<String, dynamic> json) => MapProvider(
        id: json['id'] as String,
        name: json['name'] as String,
        attribution: json['attribution'] as String?,
        isolated: json['isolated'] as bool? ?? false,
        sources: [
          for (final s in (json['sources'] as List<dynamic>? ?? const [])) MapSource.fromJson(s as Map<String, dynamic>),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (attribution != null) 'attribution': attribution,
        'isolated': isolated,
        'sources': [for (final s in sources) s.toJson()],
      };
}

/// One layer in the current stack.
class ActiveLayer {
  const ActiveLayer({
    required this.sourceId,
    required this.type,
    required this.opacity,
    required this.visible,
    required this.zIndex,
  });

  final String sourceId;
  final MapLayerType type;

  /// 0.0–1.0.
  final double opacity;
  final bool visible;

  /// Overlay order: higher is drawn on top.
  final int zIndex;

  ActiveLayer copyWith({double? opacity, bool? visible, int? zIndex}) => ActiveLayer(
        sourceId: sourceId,
        type: type,
        opacity: opacity ?? this.opacity,
        visible: visible ?? this.visible,
        zIndex: zIndex ?? this.zIndex,
      );

  factory ActiveLayer.fromJson(Map<String, dynamic> json) => ActiveLayer(
        sourceId: json['sourceId'] as String,
        type: _enumByName(MapLayerType.values, json['type'], 'layer type'),
        opacity: (json['opacity'] as num).toDouble(),
        visible: json['visible'] as bool,
        zIndex: (json['zIndex'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'type': type.name,
        'opacity': opacity,
        'visible': visible,
        'zIndex': zIndex,
      };

  @override
  bool operator ==(Object other) =>
      other is ActiveLayer &&
      other.sourceId == sourceId &&
      other.type == type &&
      other.opacity == opacity &&
      other.visible == visible &&
      other.zIndex == zIndex;

  @override
  int get hashCode => Object.hash(sourceId, type, opacity, visible, zIndex);
}

/// A named base + overlays combination, switched with one tap.
class MapPreset {
  const MapPreset({required this.id, required this.name, required this.baseSourceId, required this.overlays});

  final String id;
  final String name;
  final String baseSourceId;
  final List<ActiveLayer> overlays;

  factory MapPreset.fromJson(Map<String, dynamic> json) => MapPreset(
        id: json['id'] as String,
        name: json['name'] as String,
        baseSourceId: json['baseSourceId'] as String,
        overlays: [
          for (final o in (json['overlays'] as List<dynamic>? ?? const [])) ActiveLayer.fromJson(o as Map<String, dynamic>),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseSourceId': baseSourceId,
        'overlays': [for (final o in overlays) o.toJson()],
      };

  @override
  bool operator ==(Object other) =>
      other is MapPreset &&
      other.id == id &&
      other.name == name &&
      other.baseSourceId == baseSourceId &&
      _listEquality.equals(other.overlays, overlays);

  @override
  int get hashCode => Object.hash(id, name, baseSourceId, Object.hashAll(overlays));
}

/// What the map shows now, plus the user's favourites and presets.
class MapState {
  const MapState({
    required this.baseSourceId,
    required this.overlays,
    required this.favoriteIds,
    required this.presets,
  });

  const MapState.initial()
      : baseSourceId = null,
        overlays = const [],
        favoriteIds = const [],
        presets = const [];

  final String? baseSourceId;
  final List<ActiveLayer> overlays;
  final List<String> favoriteIds;
  final List<MapPreset> presets;

  MapState copyWith({
    String? baseSourceId,
    List<ActiveLayer>? overlays,
    List<String>? favoriteIds,
    List<MapPreset>? presets,
  }) =>
      MapState(
        baseSourceId: baseSourceId ?? this.baseSourceId,
        overlays: overlays ?? this.overlays,
        favoriteIds: favoriteIds ?? this.favoriteIds,
        presets: presets ?? this.presets,
      );

  factory MapState.fromJson(Map<String, dynamic> json) => MapState(
        baseSourceId: json['baseSourceId'] as String?,
        overlays: [
          for (final o in (json['overlays'] as List<dynamic>? ?? const [])) ActiveLayer.fromJson(o as Map<String, dynamic>),
        ],
        favoriteIds: [for (final id in (json['favoriteIds'] as List<dynamic>? ?? const [])) id as String],
        presets: [
          for (final p in (json['presets'] as List<dynamic>? ?? const [])) MapPreset.fromJson(p as Map<String, dynamic>),
        ],
      );

  Map<String, dynamic> toJson() => {
        if (baseSourceId != null) 'baseSourceId': baseSourceId,
        'overlays': [for (final o in overlays) o.toJson()],
        'favoriteIds': favoriteIds,
        'presets': [for (final p in presets) p.toJson()],
      };

  @override
  bool operator ==(Object other) =>
      other is MapState &&
      other.baseSourceId == baseSourceId &&
      _listEquality.equals(other.overlays, overlays) &&
      _listEquality.equals(other.favoriteIds, favoriteIds) &&
      _listEquality.equals(other.presets, presets);

  @override
  int get hashCode =>
      Object.hash(baseSourceId, Object.hashAll(overlays), Object.hashAll(favoriteIds), Object.hashAll(presets));
}
