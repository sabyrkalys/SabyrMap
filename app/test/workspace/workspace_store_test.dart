import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/workspace/workspace.dart';
import 'package:app/workspace/workspace_snapshot.dart';
import 'package:app/workspace/workspace_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late WorkspaceStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = WorkspaceStore(AppSettings(await SharedPreferences.getInstance()));
  });

  test('an empty store gives an empty list', () async {
    final state = await store.load();
    expect(state.workspaces, isEmpty);
    expect(state.active, isNull);
  });

  test('saveList and load round-trip', () async {
    const a = Workspace(id: 'a', name: 'Home', createdAt: 1, updatedAt: 2);
    const b = Workspace(id: 'b', name: 'Trip', createdAt: 3, updatedAt: 3);
    await store.saveList([a, b], 'b');
    final state = await store.load();
    expect(state.workspaces, [a, b]);
    expect(state.active, b);
    await store.saveList([a], 'gone');
    expect((await store.load()).activeId, isNull);
  });

  test('snapshot save, load and delete', () async {
    const snap = WorkspaceSnapshot(
      mapCenter: LandmarkLocation(latitude: 50.45, longitude: 30.52),
      mapZoom: 12.5,
      mapBearing: 30,
      displayedLayerIds: ['topo'],
      displayedMarkerPaths: ['/l/a.wpt'],
      currentSourceId: 'topo',
      favoriteSetIds: ['f'],
      proximityAlertIds: ['p'],
      primaryCoordsFormat: 'sk42',
    );
    await store.saveSnapshot('a', snap);
    expect(await store.loadSnapshot('a'), snap);
    expect(await store.loadSnapshot('b'), isNull);
    await store.deleteSnapshot('a');
    expect(await store.loadSnapshot('a'), isNull);
  });
}
