import 'package:app/landmarks/map_data/landmark_features.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/map/landmark_layer.dart';
import 'package:app/waypoints/waypoint_types.dart';
import 'package:flutter_test/flutter_test.dart';

LandmarkLocation _loc(double lat, double lon) => LandmarkLocation(latitude: lat, longitude: lon);

Map<String, dynamic> _props(Map<String, dynamic> feature) => feature['properties'] as Map<String, dynamic>;

void main() {
  group('paintColor', () {
    test('a point takes its own colour first, then the colour of its waypoint type', () {
      expect(LandmarkLayer.paintColor({'role': 'point', 'type': 'waypoint', 'color': '#123456'}), '#123456');
      expect(LandmarkLayer.paintColor({'role': 'point', 'type': 'waypoint', 'kind': 'danger'}), waypointTypeColors['danger']);
      expect(
        LandmarkLayer.paintColor({'role': 'point', 'type': 'waypoint', 'kind': 'nonsense'}),
        waypointTypeColors[defaultWaypointType],
      );
    });

    test('lines, fills and points of a route fall back to the shape colour; text to the label colour', () {
      expect(LandmarkLayer.paintColor({'role': 'line', 'type': 'route'}), LandmarkLayer.defaultShapeColor);
      expect(LandmarkLayer.paintColor({'role': 'fill', 'type': 'area'}), LandmarkLayer.defaultShapeColor);
      expect(LandmarkLayer.paintColor({'role': 'point', 'type': 'route'}), LandmarkLayer.defaultShapeColor);
      expect(LandmarkLayer.paintColor({'role': 'label', 'type': 'text'}), LandmarkLayer.defaultLabelColor);
    });
  });

  group('prepare', () {
    final route = RouteObject(
      userMetadata: LandmarkMetadata(entries: {LandmarkMetadata.nameKey: 'Тропа'}),
      waypoints: [
        WaypointObject(userMetadata: LandmarkMetadata(), location: _loc(42.0, 74.0)),
        WaypointObject(userMetadata: LandmarkMetadata(), location: _loc(42.1, 74.1)),
      ],
    );

    test('every object gets a numeric id that leads back to its landmark path', () {
      final features = [
        ...LandmarkFeatures.of('/m/a.rte', route),
        ...LandmarkFeatures.of('/m/b.wpt', WaypointObject(userMetadata: LandmarkMetadata(), location: _loc(1, 2))),
      ];
      final prepared = LandmarkLayer.prepare(features, (_, _) => null);

      expect([for (final f in prepared.features) f['id']], ['0', '1', '2', '3']);
      expect(prepared.paths, ['/m/a.rte', '/m/a.rte', '/m/a.rte', '/m/b.wpt']);
      expect([for (final f in prepared.features) _props(f)['paint_color']], everyElement(isA<String>()));
    });

    test('only a point with its own icon gets an icon image', () {
      final metadata = LandmarkMetadata(entries: {LandmarkMetadata.userIconKey: 'camp.png'});
      final features = [
        ...LandmarkFeatures.of('/m/p.wpt', WaypointObject(userMetadata: metadata, location: _loc(1, 2))),
        ...LandmarkFeatures.of('/m/q.wpt', WaypointObject(userMetadata: LandmarkMetadata(), location: _loc(1, 2))),
        ...LandmarkFeatures.of('/m/c.cir', CircleObject(userMetadata: metadata, center: _loc(1, 2), radiusMeters: 50)),
      ];
      final asked = <String>[];
      final prepared = LandmarkLayer.prepare(features, (file, color) {
        asked.add('$file $color');
        return 'img-$file';
      });

      expect(_props(prepared.features[0])['icon_image'], 'img-camp.png');
      expect(_props(prepared.features[1]).containsKey('icon_image'), isFalse);
      expect(_props(prepared.features[2]).containsKey('icon_image'), isFalse);
      expect(asked, ['camp.png ${waypointTypeColors[defaultWaypointType]}']);
    });

    test('a missing icon file leaves the point a plain dot', () {
      final metadata = LandmarkMetadata(entries: {LandmarkMetadata.userIconKey: 'gone.png'});
      final prepared = LandmarkLayer.prepare(
        LandmarkFeatures.of('/m/p.wpt', WaypointObject(userMetadata: metadata, location: _loc(1, 2))),
        (_, _) => null,
      );
      expect(_props(prepared.features.single).containsKey('icon_image'), isFalse);
    });
  });

  test('a tap on the larger invisible circle under a point finds the point', () {
    expect(LandmarkLayer.tappableLayerIds, contains(LandmarkLayer.hitLayerId));
    expect(LandmarkLayer.layerIds, contains(LandmarkLayer.hitLayerId));
  });
}
