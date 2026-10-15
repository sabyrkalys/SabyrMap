import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/drafts/waypoint_patch.dart';
import 'package:app/landmarks/models/landmark_type.dart';

import 'validation_result.dart';

/// Проверка путевой точки, круга и текста перед сохранением (у всех одна
/// точка и общие поля).
abstract final class WaypointValidator {
  static const int maxNameLength = 200;
  static const int maxCommentLength = 5000;
  static const int maxDescriptionLength = 20000;

  /// Самый большой радиус круга, м (половина окружности Земли).
  static const double maxRadiusMeters = 20000000;
  static const int maxTextLength = 1000;

  /// Проверяет черновик новой путевой точки.
  static ValidationResult validate(MarkerDraft draft) {
    final errors = <String>[];
    switch (draft.type) {
      case LandmarkType.waypoint:
        break;
      case LandmarkType.circle:
        final radius = draft.radiusMeters;
        if (radius == null || !radius.isFinite || radius <= 0 || radius > maxRadiusMeters) {
          errors.add('radiusMeters must be within (0, $maxRadiusMeters]');
        }
      case LandmarkType.text:
        final text = draft.text?.trim() ?? '';
        if (text.isEmpty) errors.add('text must not be empty');
        if (text.length > maxTextLength) errors.add('text must not exceed $maxTextLength characters');
      default:
        errors.add('WaypointValidator supports waypoints, circles and texts');
    }
    _checkCoordinates(errors, draft.longitude, draft.latitude);
    _checkFields(errors, draft.name, draft.comment, draft.description, draft.colorValue);
    return _result(errors);
  }

  /// Проверяет правку существующей путевой точки (те же правила для
  /// заданных полей).
  static ValidationResult validatePatch(WaypointPatch patch) {
    final errors = <String>[];
    _checkCoordinates(errors, patch.longitude, patch.latitude);
    _checkFields(errors, patch.name, patch.comment, patch.description, patch.colorValue);
    return _result(errors);
  }

  static void _checkCoordinates(List<String> errors, double? longitude, double? latitude) {
    if (latitude != null && (latitude < -90 || latitude > 90)) {
      errors.add('latitude must be within [-90, 90]');
    }
    if (longitude != null && (longitude < -180 || longitude > 180)) {
      errors.add('longitude must be within [-180, 180]');
    }
    if ((latitude?.isNaN ?? false) || (longitude?.isNaN ?? false)) {
      errors.add('coordinates must not be NaN');
    }
  }

  static void _checkFields(List<String> errors, String? name, String? comment, String? description, int? color) {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.length > maxNameLength) {
      errors.add('name must not exceed $maxNameLength characters');
    }
    if ((comment?.length ?? 0) > maxCommentLength) {
      errors.add('comment must not exceed $maxCommentLength characters');
    }
    if ((description?.length ?? 0) > maxDescriptionLength) {
      errors.add('description must not exceed $maxDescriptionLength characters');
    }
    if (color != null && (color < 0 || color > 0xFFFFFFFF)) {
      errors.add('colorValue must be ARGB int within [0, 0xFFFFFFFF]');
    }
  }

  static ValidationResult _result(List<String> errors) =>
      errors.isEmpty ? ValidationResult.success() : ValidationResult.failure(errors);
}
