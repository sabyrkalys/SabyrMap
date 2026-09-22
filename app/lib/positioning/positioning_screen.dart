import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tracks/track_recording_actions.dart';
import '../tracks/track_recording_controller.dart';

/// Placeholder for the positioning tab; content beyond the track record
/// toggle is not designed yet.
class PositioningScreen extends ConsumerWidget {
  const PositioningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingState = ref.watch(trackRecordingControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Позиционирование'),
        actions: [
          IconButton(
            key: const Key('track_record_toggle'),
            icon: Icon(recordingState is TrackRecordingActive ? Icons.stop_circle : Icons.fiber_manual_record),
            onPressed: () => toggleTrackRecording(context, ref, recordingState),
          ),
        ],
      ),
      body: const SizedBox.expand(),
    );
  }
}
