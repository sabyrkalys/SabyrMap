import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'waypoint_icon_store.dart';

final waypointIconAssignmentsControllerProvider =
    NotifierProvider<WaypointIconAssignmentsController, Map<String, String>>(
  WaypointIconAssignmentsController.new,
);

class WaypointIconAssignmentsController extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    // Значки в файлах: меняются вместе с индексом меток (переименование,
    // перенос, правка извне).
    final store = ref.watch(waypointIconStoreProvider);
    if (store is FileWaypointIconStore) {
      final changes = store.changes;
      changes.addListener(load);
      ref.onDispose(() => changes.removeListener(load));
    }
    return const {};
  }

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
