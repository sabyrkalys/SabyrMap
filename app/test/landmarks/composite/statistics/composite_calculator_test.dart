import 'dart:math';

import 'package:app/landmarks/composite/distance/geo_math.dart';
import 'package:app/landmarks/composite/statistics/composite_calculator.dart';
import 'package:app/landmarks/composite/statistics/elevation_profile.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  const calc = CompositeCalculator();

  /// Прямоугольник со сторонами [km] км вокруг (lat, lon).
  List<LandmarkLocation> box(double lat, double lon, double km) {
    final dLat = km * 1000 / GeoMath.earthRadiusMeters * 180 / 3.141592653589793;
    final dLon = dLat / cos(GeoMath.toRadians(lat));
    return [loc(lat, lon), loc(lat, lon + dLon), loc(lat + dLat, lon + dLon), loc(lat + dLat, lon)];
  }

  test('an empty set has length 0', () {
    expect(calc.forSet(const SetObject()).totalLengthMeters, 0);
  });

  test('a set of 3 points: the polyline length', () {
    final set = SetObject(waypoints: [wp(0, 0), wp(0, 1), wp(1, 1)]);
    final expected = Haversine.distance(loc(0, 0), loc(0, 1)) + Haversine.distance(loc(0, 1), loc(1, 1));
    expect(calc.forSet(set).totalLengthMeters, closeTo(expected, 1e-6));
    expect(calc.forSet(set).areaSquareMeters, isNull);
  });

  test('a route with elevations', () {
    final route = RouteObject(
      waypoints: [
        WaypointObject(location: loc(0, 0, ele: 100)),
        WaypointObject(location: loc(0, 0.01, ele: 150)),
        WaypointObject(location: loc(0, 0.02, ele: 120)),
      ],
    );
    final stats = calc.forRoute(route);
    expect(stats.elevationGainMeters, closeTo(50, 1e-9));
    expect(stats.elevationLossMeters, closeTo(30, 1e-9));
    expect((stats.minElevationMeters, stats.maxElevationMeters), (100, 150));
  });

  test('a track of two segments: summed length, no jump between them, duration', () {
    final a = [loc(0, 0, t: 1000), loc(0, 0.01, t: 2000)];
    final b = [loc(1, 0, t: 10000), loc(1, 0.01, t: 61000)];
    final track = TrackObject(segments: [TrackSegment(locations: a), TrackSegment(locations: b)]);
    final stats = calc.forTrack(track);
    expect(stats.totalLengthMeters, closeTo(Haversine.totalDistance(a) + Haversine.totalDistance(b), 1e-6));
    expect(stats.durationMs, 60000);
    expect(calc.forTrack(const TrackObject()).durationMs, isNull);
  });

  test('a 1×1 km square is about 1 km²', () {
    final area = AreaObject(polygons: [AreaPolygon(outline: box(50, 30, 1))]);
    final stats = calc.forArea(area);
    expect(stats.areaSquareMeters, closeTo(1e6, 1e4));
    expect(stats.perimeterMeters, closeTo(4000, 40));
  });

  test('a hole is subtracted', () {
    final area = AreaObject(
      polygons: [
        AreaPolygon(outline: box(50, 30, 2), holes: [box(50.002, 30.002, 1)]),
      ],
    );
    expect(calc.forArea(area).areaSquareMeters, closeTo(3e6, 3e4));
  });

  test('an open outline has area 0 and an open perimeter', () {
    final outline = box(50, 30, 1);
    final area = AreaObject(
      userMetadata: const LandmarkMetadata(entries: {'closed': false}),
      polygons: [AreaPolygon(outline: outline)],
    );
    final stats = calc.forArea(area);
    expect(stats.areaSquareMeters, 0);
    expect(stats.perimeterMeters, closeTo(Haversine.totalDistance(outline), 1e-6));
  });

  test('elevation profile skips points without height and filters noise', () {
    final profile = ElevationProfileBuilder.build([
      loc(0, 0, ele: 100),
      loc(0, 0.001),
      loc(0, 0.002, ele: 100.4),
      loc(0, 0.003, ele: 99.7),
      loc(0, 0.004, ele: 110),
      loc(0, 0.005, ele: 105),
    ]);
    expect(profile.points, hasLength(5));
    expect(profile.points[1].distanceMeters, closeTo(Haversine.distance(loc(0, 0), loc(0, 0.002)), 1e-6));
    expect(profile.gain, closeTo(10, 1e-9));
    expect(profile.loss, closeTo(5, 1e-9));
    expect((profile.min, profile.max), (99.7, 110));
    expect(ElevationProfileBuilder.build([loc(0, 0)]).isEmpty, isTrue);
  });

  test('metadataFor writes the statistics keys the explorer reads', () {
    final patch = calc.metadataFor(TrackObject(segments: [TrackSegment(locations: [loc(0, 0, t: 0), loc(0, 1, t: 5)])]));
    expect(patch.set.keys, containsAll(['length_m', 'duration_ms']));
    expect(patch.remove, containsAll(['elevation_gain_m', 'area_m2']));
    final area = calc.metadataFor(AreaObject(polygons: [AreaPolygon(outline: box(0, 0, 1))]));
    expect(area.set.keys, ['area_m2']);
  });
}
