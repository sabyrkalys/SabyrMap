import 'package:app/landmarks/models/landmark_location.dart';

import 'intent_kind.dart';
import 'intent_payload.dart';

/// Показать место на карте.
class DisplayLocationIntent {
  const DisplayLocationIntent._(this.payload);

  /// Нужны вид [IntentKind.displayLocation] и координаты; иначе null.
  static DisplayLocationIntent? fromPayload(IntentPayload payload) =>
      payload.kind == IntentKind.displayLocation && payload.location != null ? DisplayLocationIntent._(payload) : null;

  final IntentPayload payload;

  LandmarkLocation get location => payload.location!;
}
