import 'package:app/landmarks/models/landmark_location.dart';

import 'intent_kind.dart';
import 'intent_payload.dart';

/// Быстро создать путевую точку.
class FastWaypointIntent {
  const FastWaypointIntent._(this.payload);

  /// Нужны вид [IntentKind.fastWaypoint] и координаты; иначе null.
  static FastWaypointIntent? fromPayload(IntentPayload payload) =>
      payload.kind == IntentKind.fastWaypoint && payload.location != null ? FastWaypointIntent._(payload) : null;

  final IntentPayload payload;

  LandmarkLocation get location => payload.location!;
}
