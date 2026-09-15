import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'waypoint_icon_store.dart';

final waypointIconAssignmentsControllerProvider =
    NotifierProvider<WaypointIconAssignmentsController, Map<String, String>>(
  WaypointIconAssignmentsController.new,
);

class WaypointIconAssignmentsController extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  WaypointIconStore get _store => ref.read(waypointIconStoreProvider);

  Future<void> load() async {
    state = await _store.readAll();
  }

  Future<void> setIcon(String waypointId, String? fileName) async {
    await _store.setIcon(waypointId, fileName);
    final next = Map.of(state);
    if (fileName == null) {
      next.remove(waypointId);
    } else {
      next[waypointId] = fileName;
    }
    state = next;
  }
}
