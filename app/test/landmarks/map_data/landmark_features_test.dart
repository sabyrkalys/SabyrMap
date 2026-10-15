import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/landmarks/map_data/landmark_features.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/on_screen/on_screen_saver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../explorer/landmark_test_helpers.dart';
import '../services/fixture.dart';

void main() {
  LandmarkLocation at(double lon, double lat) => LandmarkLocation(longitude: lon, latitude: lat);
  WaypointObject wpt(String name, double lon, double lat) =>
      WaypointObject(location: at(lon, lat), userMetadata: LandmarkMetadata(entries: {'name': name}));
  List<String> roles(List<Map<String, dynamic>> fs) => [for (final f in fs) f['properties']['role'] as String];
  List<String> geometries(List<Map<String, dynamic>> fs) => [for (final f in fs) f['geometry']['type'] as String];

  test('every type becomes features with its path, role and style', () {
    final point = LandmarkFeatures.of(
      '/m/a.wpt',
      WaypointObject(
        location: at(37, 48),
        userMetadata: const LandmarkMetadata(entries: {'name': 'А', 'color': 0xFF1565C0, 'user_icon': 'БЛА/x.svg', 'type': 'post'}),
      ),
    );
    expect(point.single['geometry'], {'type': 'Point', 'coordinates': [37.0, 48.0]});
    expect(point.single['properties'], {
      'path': '/m/a.wpt',
      'type': 'waypoint',
      'role': 'point',
      'name': 'А',
      'color': '#1565C0',
      'user_icon': 'БЛА/x.svg',
      'kind': 'post',
    });

    final route = LandmarkFeatures.of('/m/r.rte', RouteObject(waypoints: [wpt('1', 37, 48), wpt('2', 37.1, 48.1)]));
    expect(roles(route), ['line', 'point', 'point']);
    expect(route[2]['properties']['index'], 1);

    expect(roles(LandmarkFeatures.of('/m/s.set', SetObject(waypoints: [wpt('1', 37, 48)]))), ['point']);

    final track = TrackObject(
      segments: [
        TrackSegment(locations: [at(37, 48), at(37.1, 48)]),
        TrackSegment(locations: [at(37.2, 48)]),
      ],
      waypoints: [wpt('Привал', 37.05, 48)],
    );
    expect(roles(LandmarkFeatures.of('/m/t.trk', track)), ['line', 'point'], reason: 'a one-point segment is not a line');

    final area = AreaObject(
      polygons: [
        AreaPolygon(outline: [at(37, 48), at(37.1, 48), at(37.1, 48.1)], holes: [[at(37.05, 48.02), at(37.06, 48.02), at(37.06, 48.03)]]),
      ],
    );
    final fill = LandmarkFeatures.of('/m/z.are', area).single;
    final rings = fill['geometry']['coordinates'] as List;
    expect((fill['properties']['role'], rings.length, (rings.first as List).length), ('fill', 2, 4));
    expect((rings.first as List).last, (rings.first as List).first, reason: 'rings are closed');
    final open = AreaObject(polygons: area.polygons, userMetadata: const LandmarkMetadata(entries: {'closed': false}));
    expect(geometries(LandmarkFeatures.of('/m/z.are', open)), ['LineString']);

    final label = LandmarkFeatures.of(
      '/m/t.lbl',
      TextObject(location: at(37, 48), text: 'Брод', userMetadata: const LandmarkMetadata(entries: {'rotation': 30})),
    ).single['properties'];
    expect((label['role'], label['text'], label['rotation']), ('label', 'Брод', 30));
  });

  test('a circle is a closed ring at the radius', () {
    final f = LandmarkFeatures.of('/m/c.cir', CircleObject(center: at(37, 48), radiusMeters: 1000)).single;
    final ring = (f['geometry']['coordinates'] as List).single as List;
    expect(ring, hasLength(LandmarkFeatures.circleVertices + 1));
    for (final c in ring) {
      final pt = c as List;
      expect(Haversine.distanceDegrees(48, 37, pt[1] as double, pt[0] as double), closeTo(1000, 2));
    }
    expect(f['properties']['radius'], 1000);
  });

  test('a landmark file gives the features of its objects with nested paths', () {
    final fs = LandmarkFeatures.of('/m/x.ldk', LdkFileObject(objects: [wpt('А', 37, 48), CircleObject(center: at(37, 48), radiusMeters: 50)]));
    expect([for (final f in fs) f['properties']['path']], ['/m/x.ldk#ldk:0', '/m/x.ldk#ldk:1']);
  });

  test('the geometry cache reads each file once per version and follows changes', () async {
    final fx = await ServicesFixture.create();
    addTearDown(fx.dispose);
    final s = fx.services;
    final a = await createWaypoint(s, 'А', fx.paths.landmarks);
    final ldk = await OnScreenSaver.saveAll(s, [a], name: 'Архив');

    final first = await s.geometry.collectionOf(s.index.items);
    final paths = [for (final f in first['features'] as List) (f as Map)['properties']['path']];
    expect(paths, unorderedEquals([a, '$ldk#ldk:0']));

    final file = await s.repository.load(a);
    await s.repository.update(a, file.withContent(file.content.withUserMetadata(file.content.userMetadata.withEntries({'name': 'Б'}))));
    final again = await s.geometry.featuresOf([s.index.byPath(a)!]);
    expect(again.single['properties']['name'], 'Б');
  });
}
