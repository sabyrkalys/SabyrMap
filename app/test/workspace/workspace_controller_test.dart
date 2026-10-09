import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/maps/layer_stack/layer_entry.dart';
import 'package:app/navigation/proximity/proximity_alert.dart';
import 'package:app/workspace/workspace_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../landmarks/services/fixture.dart';

void main() {
  late ServicesFixture f;
  late WorkspaceController c;
  setUp(() async {
    f = await ServicesFixture.create();
    c = f.services.workspaceController;
  });
  tearDown(() => f.dispose());

  test('the first launch creates Default and makes it active', () {
    expect(c.state.workspaces.single.name, 'Default');
    expect(c.state.active!.id, WorkspaceController.defaultId);
  });

  test('create adds, activate switches', () async {
    final trip = await c.create(' Trip ');
    expect(trip.name, 'Trip');
    expect(c.state.workspaces, hasLength(2));
    expect(c.state.activeId, WorkspaceController.defaultId);
    await c.activate(trip.id);
    expect(c.state.activeId, trip.id);
    expect(f.services.navigationSettings.currentWorkspace, trip.id);
    expect(() => c.activate('nope'), throwsStateError);
  });

  test('rename changes the name and updatedAt', () async {
    final trip = await c.create('Trip');
    f.now = f.now.add(const Duration(minutes: 1));
    await c.rename(trip.id, 'Hike');
    final renamed = c.state.workspaces.last;
    expect(renamed.name, 'Hike');
    expect(renamed.updatedAt, greaterThan(renamed.createdAt));
    expect(() => c.rename(trip.id, ' '), throwsArgumentError);
  });

  test('delete removes, but never the last one', () async {
    final trip = await c.create('Trip');
    await c.activate(trip.id);
    await c.delete(trip.id);
    expect(c.state.workspaces.single.id, WorkspaceController.defaultId);
    expect(c.state.activeId, WorkspaceController.defaultId);
    expect(() => c.delete(WorkspaceController.defaultId), throwsStateError);
  });

  test('activate saves the current snapshot and applies the target one', () async {
    final layers = f.services.layerStack;
    await layers.add(const LayerEntry(id: 'topo', sourceId: 'mbtiles'));
    await layers.add(const LayerEntry(id: 'hills', sourceId: 'mbtiles'));
    await layers.setVisible('hills', false);
    f.services.displayRegistry.display('/l/a.wpt');
    c.updateCamera(center: const LandmarkLocation(latitude: 50, longitude: 30), zoom: 11);
    await f.services.proximityController.add(
      ProximityAlert(id: 'camp', name: 'Camp', center: const LandmarkLocation(latitude: 0, longitude: 0), radiusMeters: 100),
    );

    final trip = await c.create('Trip');
    await c.activate(trip.id);
    expect(f.services.displayRegistry.count, 0);
    expect(f.services.proximityController.alerts, isEmpty);
    await layers.setVisible('hills', true);
    await layers.setVisible('topo', false);

    await c.activate(WorkspaceController.defaultId);
    expect(layers.state.visibleLayers.map((l) => l.id), ['topo']);
    expect(f.services.displayRegistry.isDisplayed('/l/a.wpt'), isTrue);
    expect(c.pendingCamera.zoom, 11);
    expect(f.services.proximityController.alerts.single.id, 'camp');

    await c.activate(trip.id);
    expect(layers.state.visibleLayers.map((l) => l.id), ['hills']);
  });
}
