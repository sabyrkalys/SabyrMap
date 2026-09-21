import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoints_repository.dart';

class FakeWaypointsRepository implements WaypointsRepository {
  FakeWaypointsRepository({List<Waypoint>? initial}) : items = List.of(initial ?? const []);

  final List<Waypoint> items;

  /// Set to a Waypoint for success, or a WaypointException instance to throw.
  Object? createResult;
  Object? updateResult;
  Object? deleteResult;

  /// Records the `color` argument actually passed to [update], so tests can
  /// assert on what was truly sent through rather than only on the fake's
  /// canned return value (which could coincidentally already carry the
  /// right color, masking a call site that dropped the argument).
  String? lastUpdateColor;

  @override
  Future<List<Waypoint>> list() async => List.of(items);

  @override
  Future<Waypoint> create({
    required String name,
    required String type,
    required String note,
    required String? color,
    required double lat,
    required double lng,
  }) async {
    if (createResult is WaypointException) throw createResult as WaypointException;
    return createResult as Waypoint;
  }

  @override
  Future<Waypoint> update(
    String id, {
    required String name,
    required String type,
    required String note,
    required String? color,
  }) async {
    lastUpdateColor = color;
    if (updateResult is WaypointException) throw updateResult as WaypointException;
    return updateResult as Waypoint;
  }

  @override
  Future<void> delete(String id) async {
    if (deleteResult is WaypointException) throw deleteResult as WaypointException;
  }
}
