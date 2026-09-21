import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client_provider.dart';
import 'waypoint_models.dart';
import 'waypoints_repository.dart';

final waypointsRepositoryProvider = Provider<WaypointsRepository>((ref) {
  return HttpWaypointsRepository(ref.watch(apiClientProvider));
});

final waypointsControllerProvider = NotifierProvider<WaypointsController, List<Waypoint>>(WaypointsController.new);

class WaypointsController extends Notifier<List<Waypoint>> {
  @override
  List<Waypoint> build() => const [];

  WaypointsRepository get _repository => ref.read(waypointsRepositoryProvider);

  Future<void> loadWaypoints() async {
    try {
      state = await _repository.list();
    } on WaypointException {
      // Initial-load failures aren't surfaced in this slice; the map just
      // stays at whatever it already had (empty, on first load) until the
      // next successful load.
    }
  }

  Future<Waypoint> createWaypoint({
    required String name,
    required String type,
    required String note,
    required double lat,
    required double lng,
    required String? color,
  }) async {
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    // ownerId is unknown client-side (single implicit user); the server
    // response replaces this optimistic entry.
    final optimistic = Waypoint(
      id: tempId,
      orgId: '',
      ownerId: '',
      name: name,
      type: type,
      note: note.isEmpty ? null : note,
      lat: lat,
      lng: lng,
      color: color,
      canEdit: true,
      createdAt: DateTime.now(),
    );
    state = [...state, optimistic];

    try {
      final created = await _repository.create(name: name, type: type, note: note, color: color, lat: lat, lng: lng);
      state = [for (final w in state) if (w.id == tempId) created else w];
      return created;
    } on WaypointException {
      state = [for (final w in state) if (w.id != tempId) w];
      rethrow;
    }
  }

  Future<void> updateWaypoint(
    String id, {
    required String name,
    required String type,
    required String note,
    required String? color,
  }) async {
    final index = state.indexWhere((w) => w.id == id);
    if (index == -1) return;
    final previous = state[index];
    final optimistic = Waypoint(
      id: previous.id,
      orgId: previous.orgId,
      ownerId: previous.ownerId,
      name: name,
      type: type,
      note: note.isEmpty ? null : note,
      lat: previous.lat,
      lng: previous.lng,
      color: color,
      canEdit: previous.canEdit,
      createdAt: previous.createdAt,
    );
    state = [for (final w in state) if (w.id == id) optimistic else w];

    try {
      final updated = await _repository.update(id, name: name, type: type, note: note, color: color);
      state = [for (final w in state) if (w.id == id) updated else w];
    } on WaypointException {
      state = [for (final w in state) if (w.id == id) previous else w];
      rethrow;
    }
  }

  Future<void> deleteWaypoint(String id) async {
    final index = state.indexWhere((w) => w.id == id);
    if (index == -1) return;
    final previous = state[index];
    state = [for (final w in state) if (w.id != id) w];

    try {
      await _repository.delete(id);
    } on WaypointException {
      state = [...state, previous];
      rethrow;
    }
  }
}
