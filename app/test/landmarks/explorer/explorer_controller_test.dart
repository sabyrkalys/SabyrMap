import 'dart:io';

import 'package:app/landmarks/explorer/clipboard/landmarks_clipboard.dart';
import 'package:app/landmarks/explorer/display/display_registry.dart';
import 'package:app/landmarks/explorer/explorer_controller.dart';
import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/explorer/explorer_view_mode.dart';
import 'package:app/landmarks/explorer/listing/filter_options.dart';
import 'package:app/landmarks/explorer/listing/sort_options.dart';
import 'package:app/landmarks/explorer/places/place_root.dart';
import 'package:app/landmarks/explorer/places/places_provider.dart';
import 'package:app/landmarks/explorer/selection/selection_controller.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:app/landmarks/services/folder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'explorer_fixture.dart';

void main() {
  late ExplorerFixture f;
  late ExplorerController c;
  late String downloads;

  ExplorerController build() => ExplorerController(
    folders: FolderService(f.paths, f.settings),
    places: PlacesProvider(f.paths, downloads: () async => downloads, device: () async => null),
    reader: f.reader,
    displayRegistry: DisplayRegistry(),
    selection: SelectionController(),
    clipboard: LandmarksClipboard(),
    settings: f.settings,
  );

  List<String> names() => [for (final n in c.state.nodes) n.name];

  setUp(() async {
    f = await ExplorerFixture.create();
    downloads = p.join(f.root.path, 'Download');
    Directory(downloads).createSync();
    c = build();
  });
  tearDown(() {
    c.dispose();
    f.dispose();
  });

  test('loadPlaces lists existing places once', () async {
    final places = await c.loadPlaces();
    expect(places.map((pl) => pl.kind), [PlaceRootKind.landmarks, PlaceRootKind.downloads]);
    expect(places.first.path, f.paths.landmarks);
    expect(places.first.title, 'Мои метки');

    downloads = f.paths.landmarks;
    expect(await c.loadPlaces(), hasLength(1));
    downloads = p.join(f.root.path, 'missing');
    expect(await c.loadPlaces(), hasLength(1));
  });

  test('openFolder fills nodes: folders first, then sorted items', () async {
    await f.waypoint('Beta');
    await f.waypoint('alpha');
    File(p.join(f.paths.landmarks, 'junk.txt')).writeAsStringSync('x');
    await c.openFolder(f.paths.landmarks);
    expect(c.state.currentFolder, f.paths.landmarks);
    expect(c.state.isLoading, isFalse);
    expect(names(), ['imported', 'recorded_tracks', 'alpha', 'Beta']);
    expect(c.state.nodes.first, isA<ExplorerFolderNode>());
    expect(c.state.nodes.last, isA<ExplorerItemNode>());
  });

  test('a missing folder gives an error and no nodes', () async {
    await c.openFolder(p.join(f.root.path, 'missing'));
    expect(c.state.nodes, isEmpty);
    expect(c.state.errorMessage, contains('does not exist'));
  });

  test('openPlace and goUp stay inside the place', () async {
    final place = (await c.loadPlaces()).first;
    await c.openPlace(place);
    expect(c.state.currentPlace, place);
    await c.openFolder(f.paths.importDefault);
    await c.goUp();
    expect(c.state.currentFolder, f.paths.landmarks);
    await c.goUp();
    expect(c.state.currentFolder, f.paths.landmarks);
  });

  test('setViewMode changes the state and is remembered per folder', () async {
    await c.openFolder(f.paths.landmarks);
    expect(c.state.viewMode, ExplorerViewMode.preview);
    await c.setViewMode(ExplorerViewMode.list);
    expect(c.state.viewMode, ExplorerViewMode.list);
    expect(f.settings.getString(ExplorerController.viewModeKey(f.paths.landmarks)), 'list');

    await c.openFolder(f.paths.importDefault);
    expect(c.state.viewMode, ExplorerViewMode.preview);
    await c.openFolder(f.paths.landmarks);
    expect(c.state.viewMode, ExplorerViewMode.list);
  });

  test('setSort changes the order and is remembered', () async {
    await f.waypoint('a');
    await f.waypoint('b');
    await c.openFolder(f.paths.recordedTracks);
    await c.openFolder(f.paths.landmarks);
    await c.setSort(const SortOptions(direction: SortDirection.descending));
    expect(names().skip(2), ['b', 'a']);
    expect(build().state.sort, const SortOptions(direction: SortDirection.descending));
  });

  test('distance sort waits for the screen centre', () async {
    await f.waypoint('far', lat: 55, lon: 37);
    await f.waypoint('near', lat: 50.45, lon: 30.52);
    await f.waypoint('mid', lat: 52, lon: 30);
    await c.openFolder(f.paths.landmarks);
    expect(names().skip(2), ['far', 'mid', 'near']);

    await c.setSort(const SortOptions(field: SortField.distanceFromScreenCenter));
    expect(c.state.sort.field, SortField.distanceFromScreenCenter);
    expect(c.appliedSort.field, SortField.name);
    expect(names().skip(2), ['far', 'mid', 'near']);

    await c.setScreenCenter(50.4, 30.5);
    expect(c.appliedSort.field, SortField.distanceFromScreenCenter);
    expect(names().skip(2), ['near', 'mid', 'far']);
  });

  test('setFilter narrows the list; onlyDisplayed follows the map', () async {
    final a = await f.waypoint('a');
    await f.track('t');
    await c.openFolder(f.paths.landmarks);
    await c.setFilter(const ItemFilter(onlyType: LandmarkType.track));
    expect(names().skip(2), ['t']);
    await c.setFilter(const ItemFilter(onlyDisplayed: true));
    expect(names().skip(2), isEmpty);
    c.display.display(a);
    expect(names().skip(2), ['a']);
    expect(c.allItems, hasLength(2));
  });

  test('refresh rereads the folder', () async {
    await c.openFolder(f.paths.landmarks);
    expect(c.state.nodes.whereType<ExplorerItemNode>(), isEmpty);
    await f.waypoint('new');
    await c.refresh();
    expect(c.state.nodes.whereType<ExplorerItemNode>().single.name, 'new');
  });

  test('changing the folder resets the selection', () async {
    await c.openFolder(f.paths.landmarks);
    c.selection.activate();
    c.selection.select('/a');
    await c.openFolder(f.paths.importDefault);
    expect(c.selection.state.isActive, isFalse);
    expect(c.selection.state.count, 0);
  });

  test('listeners are notified', () async {
    var notified = 0;
    c.addListener(() => notified++);
    await c.openFolder(f.paths.landmarks);
    expect(notified, greaterThanOrEqualTo(2));
  });
}
