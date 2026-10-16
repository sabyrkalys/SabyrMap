import 'package:app/landmarks/composite/drafts/track_draft.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/landmark_services_provider.dart';
import 'track_models.dart';
import 'track_name_form_sheet.dart';
import 'track_recording_controller.dart';

/// Записанный трек — файлом `.trk` в несортированные метки: появляется
/// во «Всех метках» и на карте, как нарисованный. Точки — одним сегментом,
/// с высотой, временем и точностью GPS.
Future<String?> saveRecordedTrack(
  ProviderContainer container,
  ScaffoldMessengerState messenger, {
  required String name,
  required List<TrackPoint> points,
}) async {
  final locations = [for (final p in points) p.toLocation()];
  try {
    final path = await container
        .read(landmarkServicesProvider)
        .compositeCreation
        .createTrack(
          TrackDraft(
            name: name,
            targetFolder: container.read(markerGroupFoldersProvider).unsorted,
            initialLocations: locations,
          ),
          locations.first,
        );
    messenger.showSnackBar(SnackBar(content: Text('Трек «$name» сохранён')));
    return path;
  } on ValidationException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Трек не сохранён: ${e.errors.join('; ')}')));
  } on Exception catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Трек не сохранён: $e')));
  }
  return null;
}

String _defaultTrackName() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Трек ${two(now.day)}.${two(now.month)}.${now.year} ${two(now.hour)}:${two(now.minute)}';
}

/// Starts recording if idle, or stops-and-prompts-to-save if active. Shared
/// between screens that expose the record toggle (currently the
/// ПОЗИЦИОНИРОВАНИЕ menu panel) since the underlying state lives in the root-scope
/// [trackRecordingControllerProvider], not any one screen's widget state.
///
/// The panel that calls this can be closed while a save is in flight, which
/// unmounts [context] and disposes [ref]; the container and messenger are
/// captured up front so a failure is still reported.
Future<void> toggleTrackRecording(BuildContext context, WidgetRef ref, TrackRecordingState recordingState) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  if (recordingState is TrackRecordingActive) {
    final stopResult = container.read(trackRecordingControllerProvider.notifier).stop();
    if (stopResult == null || stopResult.points.length < 2) {
      messenger.showSnackBar(const SnackBar(content: Text('Трек слишком короткий, чтобы сохранить')));
      return;
    }
    final result = await showTrackNameFormSheet(context, initialName: _defaultTrackName());
    if (result == null) return;
    await saveRecordedTrack(container, messenger, name: result.name, points: stopResult.points);
  } else {
    await container.read(trackRecordingControllerProvider.notifier).start();
    final newState = container.read(trackRecordingControllerProvider);
    if (newState is TrackRecordingIdle && newState.errorMessage != null) {
      messenger.showSnackBar(SnackBar(content: Text(newState.errorMessage!)));
    }
  }
}
