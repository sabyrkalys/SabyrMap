import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tracks_controller.dart';

/// Whether previously-saved tracks are drawn on the map. Lives outside
/// [MapScreen]'s state because the toggle now lives on the Метки tab (a
/// separate widget in the same [IndexedStack]), so both need to read/drive
/// the same value.
final tracksVisibilityControllerProvider =
    NotifierProvider<TracksVisibilityController, bool>(TracksVisibilityController.new);

class TracksVisibilityController extends Notifier<bool> {
  // Tracks whether loadTracks() has run this session. Using this instead of
  // tracksControllerProvider's emptiness avoids re-fetching after the user
  // has recorded-and-saved a track (which appends directly into that state
  // via TracksController.saveTrack, making it non-empty even though the
  // server's other previously-saved tracks were never fetched).
  bool _loaded = false;

  @override
  bool build() => false;

  Future<void> setVisible(bool visible) async {
    state = visible;
    if (visible && !_loaded) {
      await ref.read(tracksControllerProvider.notifier).loadTracks();
      _loaded = true;
    }
  }
}
