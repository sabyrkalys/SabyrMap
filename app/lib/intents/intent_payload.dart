import 'package:app/landmarks/models/landmark_location.dart';

import 'intent_kind.dart';

/// Разобранный внешний запрос.
class IntentPayload {
  const IntentPayload({
    required this.kind,
    this.location,
    this.elevationMeters,
    this.heading,
    this.timestampSec,
    this.name,
    this.comment,
    this.description,
    this.iconId,
    this.memId,
    this.trackId,
    this.setId,
    this.moveTo = false,
  });

  final IntentKind kind;

  /// null — координат нет или они неверные.
  final LandmarkLocation? location;
  final double? elevationMeters;
  final double? heading;

  /// Unix, секунды.
  final int? timestampSec;
  final String? name;
  final String? comment;
  final String? description;
  final String? iconId;
  final String? memId;
  final String? trackId;
  final String? setId;

  /// Перевести карту к точке.
  final bool moveTo;
}
