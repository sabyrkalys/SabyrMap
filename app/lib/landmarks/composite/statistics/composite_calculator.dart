import 'dart:math';

import 'package:app/landmarks/composite/distance/geo_math.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';

import 'composite_statistics.dart';
import 'elevation_profile.dart';

/// Длины, высоты, длительность и площади составных объектов.
class CompositeCalculator {
  const CompositeCalculator({this.noiseThresholdMeters = 1.0});

  /// Порог шума высот для набора/сброса, метры.
  final double noiseThresholdMeters;

  /// Набор: длина ломаной через точки в порядке хранения.
  CompositeStatistics forSet(SetObject set) =>
      CompositeStatistics(totalLengthMeters: Haversine.totalDistance([for (final w in set.waypoints) w.location]));

  /// Маршрут: длина и (если у точек есть высоты) профиль.
  CompositeStatistics forRoute(RouteObject route) {
    final locations = [for (final w in route.waypoints) w.location];
    final profile = ElevationProfileBuilder.build(locations, noiseThresholdMeters: noiseThresholdMeters);
    return CompositeStatistics(
      totalLengthMeters: Haversine.totalDistance(locations),
      elevationGainMeters: profile.gain,
      elevationLossMeters: profile.loss,
      minElevationMeters: profile.min,
      maxElevationMeters: profile.max,
    );
  }

  /// Трек: длина по всем сегментам (без перескоков между ними), высоты по
  /// сегментам, длительность — от первого до последнего времени точки.
  CompositeStatistics forTrack(TrackObject track) {
    var length = 0.0;
    var gain = 0.0;
    var loss = 0.0;
    double? minE;
    double? maxE;
    int? firstTime;
    int? lastTime;
    for (final segment in track.segments) {
      length += Haversine.segmentDistance(segment.locations);
      final profile = ElevationProfileBuilder.build(segment.locations, noiseThresholdMeters: noiseThresholdMeters);
      gain += profile.gain;
      loss += profile.loss;
      if (profile.min case final m?) minE = minE == null ? m : min(minE, m);
      if (profile.max case final m?) maxE = maxE == null ? m : max(maxE, m);
      for (final location in segment.locations) {
        final t = timeOf(location);
        if (t == null) continue;
        firstTime ??= t;
        lastTime = t;
      }
    }
    return CompositeStatistics(
      totalLengthMeters: length,
      durationMs: firstTime != null && lastTime != null && lastTime != firstTime ? lastTime - firstTime : null,
      elevationGainMeters: gain,
      elevationLossMeters: loss,
      minElevationMeters: minE,
      maxElevationMeters: maxE,
    );
  }

  /// Область: периметр по контурам и вырезам; площадь — формула площади
  /// многоугольника (shoelace) в равнопромежуточной проекции вокруг
  /// средней широты контура, минус вырезы. Незамкнутая область
  /// (`closed` = false): площадь 0, периметр по ломаной, вырезы не
  /// учитываются.
  CompositeStatistics forArea(AreaObject area) {
    final closed = isClosed(area);
    var perimeter = 0.0;
    var surface = 0.0;
    for (final polygon in area.polygons) {
      perimeter += Haversine.totalDistance(polygon.outline, close: closed);
      if (!closed) continue;
      for (final hole in polygon.holes) {
        perimeter += Haversine.totalDistance(hole, close: true);
      }
      final latitude0 = polygon.outline.isEmpty
          ? 0.0
          : polygon.outline.map((l) => l.latitude).reduce((a, b) => a + b) / polygon.outline.length;
      final holes = polygon.holes.fold(0.0, (sum, h) => sum + planarArea(h, latitude0));
      surface += max(0.0, planarArea(polygon.outline, latitude0) - holes);
    }
    return CompositeStatistics(totalLengthMeters: perimeter, perimeterMeters: perimeter, areaSquareMeters: surface);
  }

  /// Итоги любого объекта; у путевой точки — нули.
  CompositeStatistics forObject(LandmarkObject object) => switch (object) {
    SetObject o => forSet(o),
    RouteObject o => forRoute(o),
    TrackObject o => forTrack(o),
    AreaObject o => forArea(o),
    _ => const CompositeStatistics(),
  };

  /// Ключи статистики в пользовательских метаданных (их читает список
  /// проводника): ставит посчитанные, удаляет те, что посчитать нельзя.
  MetadataPatch metadataFor(LandmarkObject object) {
    final stats = forObject(object);
    final hasElevation = stats.minElevationMeters != null;
    final values = <String, Object?>{
      LandmarkMetadata.lengthKey: object is AreaObject ? null : stats.totalLengthMeters,
      LandmarkMetadata.durationKey: stats.durationMs,
      LandmarkMetadata.elevationGainKey: hasElevation ? stats.elevationGainMeters : null,
      LandmarkMetadata.areaKey: stats.areaSquareMeters,
    };
    return MetadataPatch(
      set: {for (final e in values.entries) if (e.value != null) e.key: e.value},
      remove: {for (final e in values.entries) if (e.value == null) e.key},
    );
  }

  /// Замкнута ли область (нет ключа `closed` — замкнута).
  static bool isClosed(AreaObject area) => area.userMetadata.entries[LandmarkMetadata.closedKey] != false;

  /// Время точки, Unix ms.
  static int? timeOf(LandmarkLocation location) => switch (location.valueOf(LocationValueType.utcTime)?.value) {
    final int t => t,
    _ => null,
  };

  /// Площадь контура, м², в проекции вокруг широты [latitude0].
  static double planarArea(List<LandmarkLocation> ring, double latitude0) {
    if (ring.length < 3) return 0;
    final k = cos(GeoMath.toRadians(latitude0));
    double x(LandmarkLocation l) => GeoMath.earthRadiusMeters * GeoMath.toRadians(l.longitude) * k;
    double y(LandmarkLocation l) => GeoMath.earthRadiusMeters * GeoMath.toRadians(l.latitude);
    var twice = 0.0;
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      twice += x(a) * y(b) - x(b) * y(a);
    }
    return twice.abs() / 2;
  }
}
