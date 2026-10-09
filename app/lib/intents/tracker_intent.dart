import 'dart:developer' as developer;

import 'intent_kind.dart';
import 'intent_payload.dart';

/// Действие с записью трека.
enum TrackerAction { start, stop, addWaypoint }

/// Запрос к записи трека.
class TrackerIntent {
  const TrackerIntent({required this.action, required this.payload});

  /// Для видов tracker*; иначе null.
  static TrackerIntent? fromPayload(IntentPayload payload) => switch (payload.kind) {
    IntentKind.trackerStart => TrackerIntent(action: TrackerAction.start, payload: payload),
    IntentKind.trackerStop => TrackerIntent(action: TrackerAction.stop, payload: payload),
    IntentKind.trackerAddWaypoint => TrackerIntent(action: TrackerAction.addWaypoint, payload: payload),
    _ => null,
  };

  final TrackerAction action;
  final IntentPayload payload;
}

/// Запись трека. Реальная реализация — отдельный слой.
abstract class TrackerService {
  const TrackerService();

  Future<void> handle(TrackerIntent intent);
}

/// Записи трека пока нет: запросы только записываются в лог.
class LoggingTrackerService extends TrackerService {
  const LoggingTrackerService();

  @override
  Future<void> handle(TrackerIntent intent) async =>
      developer.log('Tracker ${intent.action.name} requested; track recording is not available', name: 'sabyrmap.intents');
}
