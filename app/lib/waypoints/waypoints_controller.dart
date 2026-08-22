import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart' show apiClientProvider, tokenStorageProvider;
import '../auth/token_storage.dart';

export '../auth/auth_controller.dart' show tokenStorageProvider;
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
  TokenStorage get _storage => ref.read(tokenStorageProvider);

  Future<void> loadWaypoints() async {
    final token = await _storage.read();
    if (token == null) return;
    try {
      state = await _repository.list(token);
    } on WaypointException {
      // Initial-load failures aren't surfaced in this slice; the map just
      // stays at whatever it already had (empty, on first load) until the
      // next successful load.
    }
  }

  Future<void> createWaypoint({
    required String ownerId,
    required String name,
    required String type,
    required String note,
    required double lat,
    required double lng,
  }) async {
    final token = await _storage.read();
    if (token == null) return;

    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Waypoint(
      id: tempId,
      orgId: '',
      ownerId: ownerId,
      name: name,
      type: type,
      note: note.isEmpty ? null : note,
      lat: lat,
      lng: lng,
      canEdit: true,
      createdAt: DateTime.now(),
    );
    state = [...state, optimistic];

    try {
      final created = await _repository.create(token, name: name, type: type, note: note, lat: lat, lng: lng);
      state = [for (final w in state) if (w.id == tempId) created else w];
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
  }) async {
    final token = await _storage.read();
    if (token == null) return;

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
      canEdit: previous.canEdit,
      createdAt: previous.createdAt,
    );
    state = [for (final w in state) if (w.id == id) optimistic else w];

    try {
      final updated = await _repository.update(token, id, name: name, type: type, note: note);
      state = [for (final w in state) if (w.id == id) updated else w];
    } on WaypointException {
      state = [for (final w in state) if (w.id == id) previous else w];
      rethrow;
    }
  }

  Future<void> deleteWaypoint(String id) async {
    final token = await _storage.read();
    if (token == null) return;

    final index = state.indexWhere((w) => w.id == id);
    if (index == -1) return;
    final previous = state[index];
    state = [for (final w in state) if (w.id != id) w];

    try {
      await _repository.delete(token, id);
    } on WaypointException {
      state = [...state, previous];
      rethrow;
    }
  }
}
