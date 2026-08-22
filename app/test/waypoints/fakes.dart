import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_repository.dart';

class FakeWaypointsRepository implements WaypointsRepository {
  FakeWaypointsRepository({List<Waypoint>? initial}) : items = List.of(initial ?? const []);

  final List<Waypoint> items;

  /// Set to a Waypoint for success, or a WaypointException instance to throw.
  Object? createResult;
  Object? updateResult;
  Object? deleteResult;

  @override
  Future<List<Waypoint>> list(String token) async => List.of(items);

  @override
  Future<Waypoint> create(
    String token, {
    required String name,
    required String type,
    required String note,
    required double lat,
    required double lng,
  }) async {
    if (createResult is WaypointException) throw createResult as WaypointException;
    return createResult as Waypoint;
  }

  @override
  Future<Waypoint> update(
    String token,
    String id, {
    required String name,
    required String type,
    required String note,
  }) async {
    if (updateResult is WaypointException) throw updateResult as WaypointException;
    return updateResult as Waypoint;
  }

  @override
  Future<void> delete(String token, String id) async {
    if (deleteResult is WaypointException) throw deleteResult as WaypointException;
  }
}
