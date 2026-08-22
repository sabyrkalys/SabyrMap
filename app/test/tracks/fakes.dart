import 'package:app/tracks/track_models.dart';
import 'package:app/tracks/tracks_repository.dart';

class FakeTracksRepository implements TracksRepository {
  FakeTracksRepository({List<Track>? initial}) : items = List.of(initial ?? const []);

  final List<Track> items;

  /// Set to a Track for success, or a TrackException instance to throw.
  Object? createResult;

  @override
  Future<List<Track>> list(String token) async => List.of(items);

  @override
  Future<Track> create(String token, {required String name, required List<TrackPoint> points}) async {
    if (createResult is TrackException) throw createResult as TrackException;
    return createResult as Track;
  }
}
