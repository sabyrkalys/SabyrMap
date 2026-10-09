import 'package:app/landmarks/composite/drafts/area_draft.dart';
import 'package:app/landmarks/composite/drafts/route_draft.dart';
import 'package:app/landmarks/composite/drafts/set_draft.dart';
import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/drafts/waypoint_patch.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:app/landmarks/validation/waypoint_validator.dart';

import 'composite_validation_rules.dart';

/// Проверка черновиков и готовых составных объектов.
abstract final class CompositeValidator {
  static ValidationResult validateSet(SetDraft d) => _result([
    ..._common(d.name, d.comment, d.description, d.colorValue),
    ..._count('waypoints', d.initialWaypoints.length, CompositeValidationRules.maxWaypointsPerSet),
    ..._locations('waypoint', d.initialWaypoints),
  ]);

  static ValidationResult validateRoute(RouteDraft d) => _result([
    ..._common(d.name, d.comment, d.description, d.colorValue),
    ..._count('waypoints', d.initialWaypoints.length, CompositeValidationRules.maxWaypointsPerRoute),
    ..._locations('waypoint', d.initialWaypoints),
  ]);

  /// Пустой трек допустим.
  static ValidationResult validateTrack(TrackDraft d) => _result([
    ..._common(d.name, d.comment, d.description, d.colorValue),
    ..._count('locations', d.initialLocations.length, CompositeValidationRules.maxLocationsPerSegment),
    ..._count('waypoints', d.initialWaypoints.length, CompositeValidationRules.maxWaypointsPerTrack),
    ..._locations('location', d.initialLocations),
    ..._locations('waypoint', [for (final w in d.initialWaypoints) w.location]),
    if (d.splitGapSeconds <= 0) 'splitGapSeconds must be positive',
  ]);

  static ValidationResult validateArea(AreaDraft d) => _result([
    ..._common(d.name, d.comment, d.description, d.colorValue),
    ..._count('outline points', d.initialOutline.length, CompositeValidationRules.maxOutlinePointsPerPolygon),
    ..._locations('outline point', d.initialOutline),
    if (d.isClosed && d.initialOutline.length < CompositeValidationRules.minClosedOutlinePoints)
      'closed outline needs at least ${CompositeValidationRules.minClosedOutlinePoints} points',
  ]);

  /// Проверка объекта перед записью: пределы, координаты, длина имени.
  /// Decision: минимум точек контура здесь не проверяется — в режиме
  /// правки область строится по одной точке.
  static ValidationResult validateObject(LandmarkObject object) {
    final errors = <String>[...(_name(object.userMetadata.name))];
    switch (object) {
      case SetObject(:final waypoints):
        errors
          ..addAll(_count('waypoints', waypoints.length, CompositeValidationRules.maxWaypointsPerSet))
          ..addAll(_locations('waypoint', [for (final w in waypoints) w.location]));
      case RouteObject(:final waypoints):
        errors
          ..addAll(_count('waypoints', waypoints.length, CompositeValidationRules.maxWaypointsPerRoute))
          ..addAll(_locations('waypoint', [for (final w in waypoints) w.location]));
      case TrackObject(:final waypoints, :final segments):
        errors
          ..addAll(_count('waypoints', waypoints.length, CompositeValidationRules.maxWaypointsPerTrack))
          ..addAll(_locations('waypoint', [for (final w in waypoints) w.location]))
          ..addAll(_count('segments', segments.length, CompositeValidationRules.maxSegmentsPerTrack));
        for (final (i, s) in segments.indexed) {
          errors
            ..addAll(_count('locations in segment $i', s.locations.length, CompositeValidationRules.maxLocationsPerSegment))
            ..addAll(_locations('segment $i location', s.locations));
        }
      case AreaObject(:final polygons):
        errors.addAll(_count('polygons', polygons.length, CompositeValidationRules.maxPolygonsPerArea));
        for (final (i, poly) in polygons.indexed) {
          errors
            ..addAll(_count('outline points of polygon $i', poly.outline.length, CompositeValidationRules.maxOutlinePointsPerPolygon))
            ..addAll(_locations('polygon $i outline point', poly.outline))
            ..addAll(_count('holes of polygon $i', poly.holes.length, CompositeValidationRules.maxHolesPerPolygon));
          for (final (h, hole) in poly.holes.indexed) {
            errors
              ..addAll(_count('points of hole $h in polygon $i', hole.length, CompositeValidationRules.maxOutlinePointsPerPolygon))
              ..addAll(_locations('polygon $i hole $h point', hole));
          }
        }
      case WaypointObject(:final location):
        errors.addAll(_locations('waypoint', [location]));
      default:
        errors.add('Unsupported object ${object.runtimeType}');
    }
    return _result(errors);
  }

  /// Имя, комментарий, описание и цвет — по правилам путевой точки, имя —
  /// не длиннее [CompositeValidationRules.maxNameLength].
  static List<String> _common(String? name, String? comment, String? description, int? color) {
    final waypointRules = WaypointValidator.validatePatch(
      WaypointPatch(comment: comment, description: description, colorValue: color),
    );
    return [..._name(name), ...waypointRules.errors];
  }

  static List<String> _name(String? name) => [
    if ((name?.trim().length ?? 0) > CompositeValidationRules.maxNameLength)
      'name must not exceed ${CompositeValidationRules.maxNameLength} characters',
  ];

  static List<String> _count(String what, int count, int max) => [if (count > max) '$what: $count exceeds the limit of $max'];

  /// Первая неверная точка на каждый список (не тысячи одинаковых ошибок).
  static List<String> _locations(String what, List<LandmarkLocation> locations) {
    for (final (i, l) in locations.indexed) {
      final lat = l.latitude;
      final lon = l.longitude;
      if (lat.isNaN || lon.isNaN || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
        return ['$what $i has coordinates out of range ($lat, $lon)'];
      }
    }
    return const [];
  }

  static ValidationResult _result(List<String> errors) =>
      errors.isEmpty ? ValidationResult.success() : ValidationResult.failure(errors);
}
