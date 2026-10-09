import 'dart:developer' as developer;

import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/services/folder_service.dart';
import 'package:app/landmarks/services/marker_creation_service.dart';
import 'package:app/navigation/target/target_controller.dart';

import 'display_location_intent.dart';
import 'fast_waypoint_intent.dart';
import 'intent_kind.dart';
import 'intent_payload.dart';
import 'tracker_intent.dart';

/// Выполняет разобранные внешние запросы.
///
/// Decision: [LandmarkServices] и `WaypointService` не передаются —
/// диспетчер живёт в контейнере, а правка точек ему не нужна. Быстрая
/// точка кладётся в текущую папку проводника, если она выбрана.
class IntentDispatcher {
  IntentDispatcher(this._creation, this._target, this._folders, this._tracker);

  final MarkerCreationService _creation;
  final TargetController _target;
  final FolderService _folders;
  final TrackerService _tracker;

  /// Путь созданной последним быстрым запросом точки.
  String? lastCreatedPath;

  Future<void> dispatch(IntentPayload payload) async {
    switch (payload.kind) {
      case IntentKind.displayLocation:
        final intent = DisplayLocationIntent.fromPayload(payload);
        if (intent == null) return _ignore(payload, 'no valid location');
        await _target.setTarget(intent.location);
        if (payload.moveTo) await _target.jumpToTarget();
      case IntentKind.fastWaypoint:
        final intent = FastWaypointIntent.fromPayload(payload);
        if (intent == null) return _ignore(payload, 'no valid location');
        lastCreatedPath = await _creation.create(
          MarkerDraft(
            type: LandmarkType.waypoint,
            longitude: intent.location.longitude,
            latitude: intent.location.latitude,
            name: payload.name,
            comment: payload.comment,
            description: payload.description,
            iconId: payload.iconId,
            targetFolder: await _folders.getCurrentFolder(),
          ),
        );
      case IntentKind.trackerStart || IntentKind.trackerStop || IntentKind.trackerAddWaypoint:
        await _tracker.handle(TrackerIntent.fromPayload(payload)!);
      case IntentKind.appStop:
        _ignore(payload, 'stopping the app is up to the platform layer');
      case IntentKind.unknown:
        _ignore(payload, 'unknown action');
    }
  }

  static void _ignore(IntentPayload payload, String why) =>
      developer.log('Intent ${payload.kind.name} ignored: $why', name: 'sabyrmap.intents');
}
