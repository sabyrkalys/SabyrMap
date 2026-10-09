import 'package:app/landmarks/models/landmark_location.dart';
import 'package:collection/collection.dart';

/// Состояние пространства, которое восстанавливается при переключении.
class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    this.mapCenter,
    this.mapZoom,
    this.mapBearing,
    this.displayedLayerIds = const [],
    this.displayedMarkerPaths = const [],
    this.currentSourceId,
    this.favoriteSetIds = const [],
    this.proximityAlertIds = const [],
    this.primaryCoordsFormat,
  });

  final LandmarkLocation? mapCenter;
  final double? mapZoom;
  final double? mapBearing;

  /// Видимые слои стека.
  final List<String> displayedLayerIds;

  /// Метки, показанные на карте.
  final List<String> displayedMarkerPaths;
  final String? currentSourceId;
  final List<String> favoriteSetIds;
  final List<String> proximityAlertIds;

  /// `wgs84` или `sk42`.
  final String? primaryCoordsFormat;

  static const Object _keep = Object();

  WorkspaceSnapshot copyWith({
    Object? mapCenter = _keep,
    Object? mapZoom = _keep,
    Object? mapBearing = _keep,
    List<String>? displayedLayerIds,
    List<String>? displayedMarkerPaths,
    Object? currentSourceId = _keep,
    List<String>? favoriteSetIds,
    List<String>? proximityAlertIds,
    Object? primaryCoordsFormat = _keep,
  }) => WorkspaceSnapshot(
    mapCenter: identical(mapCenter, _keep) ? this.mapCenter : mapCenter as LandmarkLocation?,
    mapZoom: identical(mapZoom, _keep) ? this.mapZoom : mapZoom as double?,
    mapBearing: identical(mapBearing, _keep) ? this.mapBearing : mapBearing as double?,
    displayedLayerIds: displayedLayerIds ?? this.displayedLayerIds,
    displayedMarkerPaths: displayedMarkerPaths ?? this.displayedMarkerPaths,
    currentSourceId: identical(currentSourceId, _keep) ? this.currentSourceId : currentSourceId as String?,
    favoriteSetIds: favoriteSetIds ?? this.favoriteSetIds,
    proximityAlertIds: proximityAlertIds ?? this.proximityAlertIds,
    primaryCoordsFormat: identical(primaryCoordsFormat, _keep) ? this.primaryCoordsFormat : primaryCoordsFormat as String?,
  );

  Map<String, Object?> toJson() => {
    'center': mapCenter == null ? null : {'lat': mapCenter!.latitude, 'lon': mapCenter!.longitude},
    'zoom': mapZoom,
    'bearing': mapBearing,
    'layers': displayedLayerIds,
    'markers': displayedMarkerPaths,
    'source': currentSourceId,
    'favoriteSets': favoriteSetIds,
    'proximityAlerts': proximityAlertIds,
    'coords': primaryCoordsFormat,
  };

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) => [for (final v in json[key] as List<dynamic>? ?? const []) v as String];
    final center = json['center'] as Map<String, dynamic>?;
    return WorkspaceSnapshot(
      mapCenter: center == null
          ? null
          : LandmarkLocation(latitude: (center['lat'] as num).toDouble(), longitude: (center['lon'] as num).toDouble()),
      mapZoom: (json['zoom'] as num?)?.toDouble(),
      mapBearing: (json['bearing'] as num?)?.toDouble(),
      displayedLayerIds: strings('layers'),
      displayedMarkerPaths: strings('markers'),
      currentSourceId: json['source'] as String?,
      favoriteSetIds: strings('favoriteSets'),
      proximityAlertIds: strings('proximityAlerts'),
      primaryCoordsFormat: json['coords'] as String?,
    );
  }

  static const _list = ListEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is WorkspaceSnapshot &&
      other.mapCenter == mapCenter &&
      other.mapZoom == mapZoom &&
      other.mapBearing == mapBearing &&
      _list.equals(other.displayedLayerIds, displayedLayerIds) &&
      _list.equals(other.displayedMarkerPaths, displayedMarkerPaths) &&
      other.currentSourceId == currentSourceId &&
      _list.equals(other.favoriteSetIds, favoriteSetIds) &&
      _list.equals(other.proximityAlertIds, proximityAlertIds) &&
      other.primaryCoordsFormat == primaryCoordsFormat;

  @override
  int get hashCode => Object.hash(mapCenter, mapZoom, mapBearing, currentSourceId, primaryCoordsFormat);
}
