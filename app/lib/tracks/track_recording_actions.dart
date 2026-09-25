import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'track_models.dart';
import 'track_name_form_sheet.dart';
import 'track_recording_controller.dart';
import 'tracks_controller.dart';

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
    try {
      await container.read(tracksControllerProvider.notifier).saveTrack(
            name: result.name,
            points: stopResult.points,
            startedAt: stopResult.startedAt,
            finishedAt: stopResult.finishedAt,
          );
    } on TrackException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  } else {
    await container.read(trackRecordingControllerProvider.notifier).start();
    final newState = container.read(trackRecordingControllerProvider);
    if (newState is TrackRecordingIdle && newState.errorMessage != null) {
      messenger.showSnackBar(SnackBar(content: Text(newState.errorMessage!)));
    }
  }
}
