import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client_provider.dart';
import 'track_models.dart';
import 'tracks_repository.dart';

final tracksRepositoryProvider = Provider<TracksRepository>((ref) {
  return HttpTracksRepository(ref.watch(apiClientProvider));
});

final tracksControllerProvider = NotifierProvider<TracksController, List<Track>>(TracksController.new);

class TracksController extends Notifier<List<Track>> {
  @override
  List<Track> build() => const [];

  TracksRepository get _repository => ref.read(tracksRepositoryProvider);

  Future<void> loadTracks() async {
    try {
      state = await _repository.list();
    } on TrackException {
      // Same intentional silent-swallow as WaypointsController.loadWaypoints():
      // an initial-load failure isn't surfaced in this slice.
    }
  }

  /// No optimistic insert: unlike a waypoint, a just-recorded track has no
  /// "immediately visible on the map" expectation before the user has even
  /// confirmed the save form, so there's nothing to roll back on failure —
  /// [TrackException] simply propagates to the caller.
  Future<void> saveTrack({
    required String name,
    required List<TrackPoint> points,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    final created = await _repository.create(
      name: name,
      points: points,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
    state = [...state, created];
  }
}
