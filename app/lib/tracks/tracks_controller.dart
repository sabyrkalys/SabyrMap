import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart' show apiClientProvider, tokenStorageProvider;
import '../auth/token_storage.dart';

export '../auth/auth_controller.dart' show tokenStorageProvider;
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
  TokenStorage get _storage => ref.read(tokenStorageProvider);

  Future<void> loadTracks() async {
    final token = await _storage.read();
    if (token == null) return;
    try {
      state = await _repository.list(token);
    } on TrackException {
      // Same intentional silent-swallow as WaypointsController.loadWaypoints():
      // an initial-load failure isn't surfaced in this slice.
    }
  }

  /// No optimistic insert: unlike a waypoint, a just-recorded track has no
  /// "immediately visible on the map" expectation before the user has even
  /// confirmed the save form, so there's nothing to roll back on failure —
  /// [TrackException] simply propagates to the caller.
  Future<void> saveTrack({required String name, required List<TrackPoint> points}) async {
    final token = await _storage.read();
    if (token == null) return;
    final created = await _repository.create(token, name: name, points: points);
    state = [...state, created];
  }
}
